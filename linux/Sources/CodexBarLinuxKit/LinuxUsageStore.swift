import CodexBarCore
import Foundation

/// Owns provider state and drives refreshes.
///
/// State is guarded by a lock rather than an actor because the GTK main loop
/// reads it synchronously when rendering, and hopping through an actor would
/// mean the UI could only ever show data one loop iteration stale.
public final class LinuxUsageStore: @unchecked Sendable {
    public typealias ProviderFetch = @Sendable (
        ProviderDescriptor,
        ProviderSourceMode,
        ProviderConfig?,
        ProviderSettingsSnapshot?) async -> ProviderFetchOutcome

    private let lock = NSLock()
    private var views: [String: ProviderView] = [:]
    private var records: [String: ProviderRefreshRecord] = [:]
    private var order: [String] = []

    private let fetch: ProviderFetch
    private let onSnapshot: @Sendable (ProviderSnapshotPayload) -> Void
    private let onRefreshRecord: @Sendable (ProviderRefreshRecord) -> Void
    private let configStore: CodexBarConfigStore
    private let kiloOrganizations: KiloOrganizationsState
    private let onKiloOrganizationsChange: @Sendable () -> Void
    private let historyStore: LinuxPlanHistoryStore?
    private let costStore: LinuxCostStore?
    private var defaultHistoryStore: LinuxPlanHistoryStore?

    public init(
        configStore: CodexBarConfigStore = CodexBarConfigStore(),
        kiloOrganizations: KiloOrganizationsState = KiloOrganizationsState(),
        onKiloOrganizationsChange: @escaping @Sendable () -> Void = {},
        historyStore: LinuxPlanHistoryStore? = nil,
        costStore: LinuxCostStore? = nil,
        fetch: @escaping ProviderFetch = { descriptor, sourceMode, config, settings in
            await UsageRefresher().fetch(
                descriptor: descriptor,
                sourceMode: sourceMode,
                config: config,
                settings: settings)
        },
        onRefreshRecord: @escaping @Sendable (ProviderRefreshRecord) -> Void = { _ in },
        onSnapshot: @escaping @Sendable (ProviderSnapshotPayload) -> Void)
    {
        self.configStore = configStore
        self.kiloOrganizations = kiloOrganizations
        self.onKiloOrganizationsChange = onKiloOrganizationsChange
        self.historyStore = historyStore
        self.costStore = costStore
        self.fetch = fetch
        self.onRefreshRecord = onRefreshRecord
        self.onSnapshot = onSnapshot
        self.seedPlaceholders()
    }

    private func loadConfig() -> CodexBarConfig? {
        try? self.configStore.load()
    }

    private func seedPlaceholders() {
        let config = self.loadConfig()
        let descriptors = ProviderCatalog.enabledProviders(config: config)
        self.lock.lock()
        self.order = descriptors.map { $0.id.rawValue }
        for descriptor in descriptors {
            self.views[descriptor.id.rawValue] = ProviderCatalog.placeholderView(
                for: descriptor,
                enabled: true)
        }
        self.lock.unlock()
    }

    public func currentPayload() -> ProviderSnapshotPayload {
        self.lock.lock()
        let providers = self.order.compactMap { self.views[$0] }
        self.lock.unlock()
        // Enrichment reads the history/cost stores, whose locks must never be
        // taken under the views lock — hence the copy-then-decorate split.
        return ProviderSnapshotPayload(
            generatedAt: Date(),
            providers: providers.map(self.enriched))
    }

    /// Re-sends the current state. Cost scans finish after the refresh that
    /// triggered them; this is how their results reach the popup.
    public func republish() {
        self.onSnapshot(self.currentPayload())
    }

    private func enriched(_ view: ProviderView) -> ProviderView {
        var view = view
        view.cost = self.costStore?.view(providerID: view.id)
        let series = view.windows.compactMap { window -> UtilizationHistorySeries? in
            guard let loaded = try? self.resolvedHistoryStore()?.load(
                providerID: view.id,
                windowID: window.id),
                loaded.segments.contains(where: { !$0.points.isEmpty })
            else { return nil }
            return loaded
        }
        view.history = series.isEmpty ? nil : series
        return view
    }

    private func store(_ view: ProviderView) {
        self.lock.lock()
        self.views[view.id] = view
        self.lock.unlock()
        self.onSnapshot(self.currentPayload())
    }

    private func store(_ record: ProviderRefreshRecord) {
        self.lock.lock()
        self.views[record.view.id] = record.view
        self.records[record.view.id] = record
        self.lock.unlock()
        self.onSnapshot(self.currentPayload())
        self.recordHistory(record)
        self.refreshCost(record)
        self.onRefreshRecord(record)
    }

    /// Refreshes every enabled provider concurrently, publishing each card as
    /// soon as it lands so a slow provider never blocks the rest.
    public func refreshAll() {
        let config = self.loadConfig()
        let descriptors = ProviderCatalog.enabledProviders(config: config)
        for descriptor in descriptors {
            self.startRefresh(descriptor: descriptor, config: config)
        }
    }

    public func refresh(providerID: String) {
        guard let provider = UsageProvider(rawValue: providerID) else { return }
        let config = self.loadConfig()
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        self.startRefresh(descriptor: descriptor, config: config)
    }

    private func startRefresh(descriptor: ProviderDescriptor, config: CodexBarConfig?) {
        let mode = UsageRefresher.sourceMode(for: descriptor.id, config: config)
        let providerConfig = config?.providers.first { $0.id == descriptor.id }
        if descriptor.id == .kilo,
           self.kiloScopes(config: providerConfig).count > 1
        {
            self.startKiloScopeRefresh(descriptor: descriptor, config: providerConfig)
            return
        }
        let settings = LinuxSettingsSnapshot.make(config: config)
        let fetch = self.fetch
        Task.detached { [weak self] in
            guard let self else { return }
            let outcome = await fetch(descriptor, mode, providerConfig, settings)
            let view: ProviderView
            let usage: UsageSnapshot?
            switch outcome.result {
            case let .success(fetched):
                usage = fetched.usage
                view = SnapshotBuilder.view(
                    descriptor: descriptor,
                    enabled: true,
                    usage: fetched.usage,
                    sourceLabel: fetched.sourceLabel)
            case let .failure(error):
                usage = nil
                view = SnapshotBuilder.failureView(
                    descriptor: descriptor,
                    enabled: true,
                    error: error)
            }
            self.store(ProviderRefreshRecord(view: view, snapshot: usage, outcome: outcome))
        }
    }

    private func recordHistory(_ record: ProviderRefreshRecord) {
        guard let historyStore = self.resolvedHistoryStore(),
              let snapshot = record.snapshot
        else { return }
        let capturedAt = snapshot.updatedAt
        let baseWindows: [(String, RateWindow?)] = [
            ("primary", snapshot.primary),
            ("secondary", snapshot.secondary),
            ("tertiary", snapshot.tertiary),
        ]
        for (windowID, window) in baseWindows {
            guard let window, window.usedPercent.isFinite else { continue }
            try? historyStore.record(
                providerID: record.view.id,
                windowID: windowID,
                point: UtilizationHistoryPoint(
                    capturedAt: capturedAt,
                    usedPercent: window.usedPercent,
                    resetsAt: window.resetsAt))
        }
        for named in snapshot.extraRateWindows ?? [] where named.usageKnown && named.window.usedPercent.isFinite {
            try? historyStore.record(
                providerID: record.view.id,
                windowID: named.id,
                point: UtilizationHistoryPoint(
                    capturedAt: capturedAt,
                    usedPercent: named.window.usedPercent,
                    resetsAt: named.window.resetsAt))
        }
    }

    private func resolvedHistoryStore() -> LinuxPlanHistoryStore? {
        self.lock.withLock {
            if let historyStore = self.historyStore { return historyStore }
            if self.defaultHistoryStore == nil {
                self.defaultHistoryStore = try? LinuxPlanHistoryStore()
            }
            return self.defaultHistoryStore
        }
    }

    public func costState(providerID: String) -> ProviderCostState? {
        self.costStore?.state(providerID: providerID)
    }

    private func refreshCost(_ record: ProviderRefreshRecord) {
        guard let costStore = self.costStore,
              let provider = UsageProvider(rawValue: record.view.id),
              let config = self.loadConfig()?.providerConfig(for: provider)
        else { return }
        Task.detached {
            await costStore.refresh(providerID: record.view.id, config: config)
        }
    }

    private func kiloScopes(config: ProviderConfig?) -> [KiloUsageScope] {
        let organizations = config?.kiloKnownOrganizations ?? []
        let organizationsByID = Dictionary(uniqueKeysWithValues: organizations.map { ($0.id, $0) })
        let enabledIDs = config?.kiloEnabledOrganizationIDs ?? []
        let organizationScopes = enabledIDs.compactMap { id -> KiloUsageScope? in
            guard let organization = organizationsByID[id] else { return nil }
            return .organization(id: organization.id, name: organization.name)
        }
        return [.personal] + organizationScopes
    }

    private func startKiloScopeRefresh(descriptor: ProviderDescriptor, config: ProviderConfig?) {
        let scopes = self.kiloScopes(config: config)
        let source = Self.kiloSourceMode(config?.source)
        let environment = ProcessInfo.processInfo.environment
        self.kiloOrganizations.beginRefresh()
        self.onKiloOrganizationsChange()

        Task.detached { [weak self] in
            guard let self else { return }
            let token: KiloResolvedBearerToken
            do {
                token = try KiloBearerTokenResolver.resolve(
                    source: source,
                    apiKey: config?.sanitizedAPIKey,
                    environment: environment)
            } catch {
                let failedScopes = scopes.map {
                    KiloScopeView(
                        id: $0.scopeIdentifier,
                        title: $0.displayName,
                        view: nil,
                        errorMessage: "Could not refresh \($0.displayName).")
                }
                self.kiloOrganizations.finishScopeRefresh(scopes: failedScopes)
                self.onKiloOrganizationsChange()
                return
            }

            let ordered = await KiloOrganizationCoordinator.refreshScopes(scopes) { scope in
                let usage = try await KiloUsageFetcher.fetchUsage(
                    apiKey: token.token,
                    scope: scope,
                    environment: environment).toUsageSnapshot()
                var view = SnapshotBuilder.view(
                    descriptor: descriptor,
                    enabled: true,
                    usage: usage,
                    sourceLabel: token.sourceLabel)
                view.id = "\(descriptor.id.rawValue):\(scope.scopeIdentifier)"
                view.displayName = "\(descriptor.metadata.displayName) — \(scope.displayName)"
                return KiloScopeView(
                    id: scope.scopeIdentifier,
                    title: scope.displayName,
                    view: view,
                    errorMessage: nil)
            }
            self.kiloOrganizations.finishScopeRefresh(scopes: ordered)
            self.onKiloOrganizationsChange()

            if var personal = ordered.first(where: { $0.id == KiloUsageScope.personal.scopeIdentifier })?.view {
                personal.id = descriptor.id.rawValue
                personal.displayName = descriptor.metadata.displayName
                self.store(personal)
            } else {
                self.store(ProviderView(
                    id: descriptor.id.rawValue,
                    displayName: descriptor.metadata.displayName,
                    iconResourceName: descriptor.branding.iconResourceName,
                    iconSVG: ProviderIcons.svg(named: descriptor.branding.iconResourceName),
                    accentColorHex: descriptor.branding.color.hexString,
                    enabled: true,
                    errorMessage: "Could not refresh Personal."))
            }
        }
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

    private var refreshTask: Task<Void, Never>?

    /// Refreshes every `intervalSeconds` until stopped. A fixed interval is
    /// enough for M2; adaptive scheduling arrives with the rest of the
    /// refresh policy later.
    public func startPeriodicRefresh(intervalSeconds: Double = 300) {
        self.stopPeriodicRefresh()
        self.refreshTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                guard !Task.isCancelled else { return }
                self?.refreshAll()
            }
        }
    }

    public func stopPeriodicRefresh() {
        self.refreshTask?.cancel()
        self.refreshTask = nil
    }

    /// Re-arms the timer from the user's choice. `startPeriodicRefresh`
    /// already stops the previous task, so no timer chain can accumulate.
    public func applyRefreshInterval(_ interval: RefreshInterval) {
        guard let seconds = interval.seconds else {
            self.stopPeriodicRefresh()
            return
        }
        self.startPeriodicRefresh(intervalSeconds: seconds)
    }

    /// Rebuilds membership/order from the latest shared config. Existing
    /// views survive, newly enabled providers start as placeholders, and
    /// disabled providers disappear before the next fetch.
    public func reconcileProviders(refresh: Bool = true) {
        let config = self.loadConfig()
        let descriptors = ProviderCatalog.enabledProviders(config: config)
        let enabledIDs = Set(descriptors.map { $0.id.rawValue })
        self.lock.lock()
        self.order = descriptors.map { $0.id.rawValue }
        self.views = self.views.filter { enabledIDs.contains($0.key) }
        self.records = self.records.filter { enabledIDs.contains($0.key) }
        for descriptor in descriptors where self.views[descriptor.id.rawValue] == nil {
            self.views[descriptor.id.rawValue] = ProviderCatalog.placeholderView(
                for: descriptor, enabled: true)
        }
        self.lock.unlock()
        self.onSnapshot(self.currentPayload())
        if refresh {
            for descriptor in descriptors {
                self.startRefresh(descriptor: descriptor, config: config)
            }
        }
    }

    /// The largest `usedPercent` across every window of every provider, for
    /// the tray label. Nil when nothing has loaded yet.
    public func highestUsedPercent() -> Double? {
        self.lock.lock()
        defer { self.lock.unlock() }
        let percentages = self.views.values.flatMap { $0.windows.map(\.usedPercent) }
        return percentages.max()
    }
}
