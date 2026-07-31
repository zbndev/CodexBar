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

    public init(onSnapshot: @escaping @Sendable (ProviderSnapshotPayload) -> Void) {
        self.onSnapshot = onSnapshot
        self.seedPlaceholders()
    }

    private func loadConfig() -> CodexBarConfig? {
        try? CodexBarConfigStore().load()
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
        let refresher = self.refresher
        Task.detached { [weak self] in
            guard let self else { return }
            let result = await refresher.fetch(descriptor: descriptor, sourceMode: mode)
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
}
