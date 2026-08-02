import CodexBarCore
import Foundation

/// Owns settings state for the settings window: assembles the payload,
/// applies edits, and persists through the two stores.
///
/// `onChange` fires after every successful apply so `main.swift` can
/// re-publish the payload to the web UI and re-arm anything the settings
/// affect (refresh timer, tray label, popup display prefs — Task 9).
public final class SettingsCoordinator: @unchecked Sendable {
    public enum CoordinatorError: Error, Equatable {
        case unknownProvider(String)
    }

    private let configStore: CodexBarConfigStore
    private let settingsStore: LinuxSettingsStore
    private let onChange: @Sendable () -> Void
    private let kiloOrganizationFetch: @Sendable (String, [String: String]) async throws -> [KiloOrganization]
    public let kiloOrganizations: KiloOrganizationsState

    public init(
        configStore: CodexBarConfigStore,
        settingsStore: LinuxSettingsStore,
        kiloOrganizations: KiloOrganizationsState? = nil,
        kiloOrganizationFetch: @escaping @Sendable (String, [String: String]) async throws -> [KiloOrganization] = {
            apiKey, environment in
            try await KiloUsageFetcher.fetchOrganizations(apiKey: apiKey, environment: environment)
        },
        onChange: @escaping @Sendable () -> Void)
    {
        self.configStore = configStore
        self.settingsStore = settingsStore
        self.onChange = onChange
        self.kiloOrganizationFetch = kiloOrganizationFetch
        let config = try? configStore.load()
        let provider = config?.providerConfig(for: .kilo)
        let organizations = provider?.kiloKnownOrganizations ?? []
        let enabledIDs = (provider?.kiloEnabledOrganizationIDs ?? []).filter { id in
            organizations.contains(where: { $0.id == id })
        }
        if let kiloOrganizations {
            self.kiloOrganizations = kiloOrganizations
            if kiloOrganizations.payload().organizations.isEmpty,
               kiloOrganizations.payload().scopes.isEmpty
            {
                kiloOrganizations.replace(organizations: organizations, enabledIDs: enabledIDs)
            }
        } else {
            self.kiloOrganizations = KiloOrganizationsState(payload: KiloOrganizationsPayload(
                organizations: organizations,
                enabledIDs: enabledIDs))
        }
    }

    public func linuxSettings() -> LinuxSettings {
        self.settingsStore.load()
    }

    public func payload() -> SettingsPayload {
        let config = try? self.configStore.load()
        let descriptors = ProviderDescriptorRegistry.all
        let panes = descriptors.map { descriptor in
            ProviderPaneGenerator.pane(
                for: descriptor,
                config: config?.providers.first { $0.id == descriptor.id })
        }
        let settings = self.linuxSettings()
        let hooks = config?.hooks ?? HooksConfig()
        return SettingsPayload(
            generatedAt: Date(),
            settings: settings,
            general: GeneralPaneCatalog.panes(settings: settings, hooks: hooks),
            providers: panes,
            managedCodexAccounts: self.managedCodexAccountViews(config: config),
            kiloOrganizations: self.kiloOrganizations.payload(),
            hooks: hooks,
            localization: LocalizationCatalog.load(locale: settings.language))
    }

    /// Read-only view of one provider's stored config — the login
    /// coordinator reads the enterprise host and existing token accounts
    /// from it before starting a flow.
    public func providerConfig(id: String) -> ProviderConfig? {
        // Same load path as payload().
        (try? self.configStore.load())?.providers.first { $0.id.rawValue == id }
    }

    public func applyProviderPatch(id: String, patch: ProviderConfigPatch) throws {
        guard let provider = UsageProvider(rawValue: id) else {
            throw CoordinatorError.unknownProvider(id)
        }
        var config = try self.configStore.load() ?? CodexBarConfig.makeDefault()
        if let index = config.providers.firstIndex(where: { $0.id == provider }) {
            config.providers[index] = patch.applying(to: config.providers[index])
        } else {
            config.providers.append(patch.applying(to: ProviderConfig(id: provider)))
        }
        try self.configStore.save(config)
        self.onChange()
    }

    public func applySettings(_ settings: LinuxSettings) throws {
        try self.settingsStore.save(settings)
        self.onChange()
    }

    /// Dedicated commands rather than patch fields: here a nil value means
    /// "clear the override", whereas an omitted `ProviderConfigPatch` key
    /// means "unchanged". Keeping them separate avoids a tri-state encoding.
    public func replaceTokenAccounts(
        providerID: String,
        data: ProviderTokenAccountData?) throws
    {
        try self.updateProvider(id: providerID) { $0.tokenAccounts = data }
    }

    public func updateQuotaWarnings(
        providerID: String,
        config warnings: QuotaWarningConfig?) throws
    {
        try self.updateProvider(id: providerID) { $0.quotaWarnings = warnings }
    }

    public func selectManagedCodexAccount(id: UUID?) throws {
        try self.updateProvider(id: UsageProvider.codex.rawValue) {
            $0.codexActiveSource = id.map(CodexActiveSource.managedAccount) ?? .liveSystem
        }
    }

    public func refreshKiloOrganizations() async {
        let config = try? self.configStore.load()
        let provider = config?.providerConfig(for: .kilo)
        let source = Self.kiloSourceMode(provider?.source)
        let environment = ProcessInfo.processInfo.environment

        self.kiloOrganizations.beginRefresh()
        self.onChange()

        do {
            let token = try KiloBearerTokenResolver.resolve(
                source: source,
                apiKey: provider?.sanitizedAPIKey,
                environment: environment)
            let result = try await KiloOrganizationCoordinator(fetch: {
                try await self.kiloOrganizationFetch(token.token, environment)
            }).refresh(previousEnabledIDs: provider?.kiloEnabledOrganizationIDs ?? [])
            try self.updateProvider(id: UsageProvider.kilo.rawValue, mutation: { entry in
                entry.kiloKnownOrganizations = result.organizations.isEmpty ? nil : result.organizations
                entry.kiloEnabledOrganizationIDs = result.enabledIDs.isEmpty ? nil : result.enabledIDs
            }, didPersist: {
                self.kiloOrganizations.replace(
                    organizations: result.organizations,
                    enabledIDs: result.enabledIDs)
            })
        } catch {
            self.kiloOrganizations.failRefresh()
            self.onChange()
        }
    }

    public func setKiloOrganizationEnabled(id: String, enabled: Bool) throws {
        let current = self.kiloOrganizations.payload()
        guard current.organizations.contains(where: { $0.id == id }) else { return }
        var enabledIDs = current.enabledIDs.filter { candidate in
            current.organizations.contains(where: { $0.id == candidate })
        }
        if enabled {
            if !enabledIDs.contains(id) {
                enabledIDs.append(id)
            }
        } else {
            enabledIDs.removeAll { $0 == id }
        }
        try self.updateProvider(id: UsageProvider.kilo.rawValue, mutation: { entry in
            entry.kiloKnownOrganizations = current.organizations.isEmpty ? nil : current.organizations
            entry.kiloEnabledOrganizationIDs = enabledIDs.isEmpty ? nil : enabledIDs
        }, didPersist: {
            self.kiloOrganizations.replace(
                organizations: current.organizations,
                enabledIDs: enabledIDs,
                scopes: current.scopes)
        })
    }

    public func managedCodexAccountsDidChange() {
        self.onChange()
    }

    private func managedCodexAccountViews(config: CodexBarConfig?) -> [ManagedCodexAccountView] {
        let activeID: UUID? = if case let .managedAccount(id)? = config?.providerConfig(for: .codex)?.codexActiveSource {
            id
        } else {
            nil
        }
        let store = FileManagedCodexAccountStore(
            fileURL: LinuxManagedCodexAccountCoordinator.defaultStoreURL())
        guard let accounts = try? store.loadAccounts() else { return [] }
        return accounts.accounts.map { ManagedCodexAccountView(account: $0, isActive: $0.id == activeID) }
    }

    private func updateProvider(
        id: String,
        mutation: (inout ProviderConfig) -> Void,
        didPersist: (() -> Void)? = nil) throws
    {
        guard let provider = UsageProvider(rawValue: id) else {
            throw CoordinatorError.unknownProvider(id)
        }
        var config = try self.configStore.load() ?? CodexBarConfig.makeDefault()
        let index: Int
        if let existing = config.providers.firstIndex(where: { $0.id == provider }) {
            index = existing
        } else {
            config.providers.append(ProviderConfig(id: provider))
            index = config.providers.index(before: config.providers.endIndex)
        }
        mutation(&config.providers[index])
        try self.configStore.save(config)
        didPersist?()
        self.onChange()
    }

    private static func kiloSourceMode(_ source: ProviderSourceMode?) -> KiloUsageDataSource {
        switch source {
        case .api:
            .api
        case .cli:
            .cli
        case .auto, .web, .oauth, nil:
            .auto
        }
    }

    public func applyHooks(_ hooks: HooksConfig) throws {
        var config = try self.configStore.load() ?? CodexBarConfig.makeDefault()
        config.hooks = hooks
        try self.configStore.save(config)
        self.onChange()
    }

    /// Re-sends the full payload to whoever is listening. Called after
    /// every apply (through `onChange` in main.swift) and on
    /// `settingsReady`.
    public func republish() {
        self.onChange()
    }

    /// Surfaces a save failure to the web UI. The closure is wired to the
    /// bridge by `SettingsWindow`.
    public func reportError(_ message: String) {
        self.onError?(message)
    }

    public var onError: (@Sendable (String) -> Void)?
}
