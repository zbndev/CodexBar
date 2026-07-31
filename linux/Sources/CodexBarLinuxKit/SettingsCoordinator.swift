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

    public init(
        configStore: CodexBarConfigStore,
        settingsStore: LinuxSettingsStore,
        onChange: @escaping @Sendable () -> Void)
    {
        self.configStore = configStore
        self.settingsStore = settingsStore
        self.onChange = onChange
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
            hooks: hooks)
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
