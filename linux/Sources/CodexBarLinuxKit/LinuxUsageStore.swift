import CodexBarCore
import Foundation

/// Owns provider state and drives refreshes.
///
/// State is guarded by a lock rather than an actor because the GTK main loop
/// reads it synchronously when rendering, and hopping through an actor would
/// mean the UI could only ever show data one loop iteration stale.
public final class LinuxUsageStore: @unchecked Sendable {
    private let lock = NSLock()
    private var views: [String: ProviderView] = [:]
    private var order: [String] = []

    private let refresher = UsageRefresher()
    private let onSnapshot: @Sendable (ProviderSnapshotPayload) -> Void
    private let configStore: CodexBarConfigStore

    public init(
        configStore: CodexBarConfigStore = CodexBarConfigStore(),
        onSnapshot: @escaping @Sendable (ProviderSnapshotPayload) -> Void)
    {
        self.configStore = configStore
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
        defer { self.lock.unlock() }
        let providers = self.order.compactMap { self.views[$0] }
        return ProviderSnapshotPayload(generatedAt: Date(), providers: providers)
    }

    private func store(_ view: ProviderView) {
        self.lock.lock()
        self.views[view.id] = view
        self.lock.unlock()
        self.onSnapshot(self.currentPayload())
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
        let refresher = self.refresher
        Task.detached { [weak self] in
            guard let self else { return }
            let result = await refresher.fetch(
                descriptor: descriptor,
                sourceMode: mode,
                config: providerConfig)
            let view: ProviderView
            switch result {
            case let .success(fetched):
                view = SnapshotBuilder.view(
                    descriptor: descriptor,
                    enabled: true,
                    usage: fetched.usage,
                    sourceLabel: fetched.sourceLabel)
            case let .failure(error):
                view = SnapshotBuilder.failureView(
                    descriptor: descriptor,
                    enabled: true,
                    error: error)
            }
            self.store(view)
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
