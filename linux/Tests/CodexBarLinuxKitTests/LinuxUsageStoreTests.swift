import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private final class PayloadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var payloads: [ProviderSnapshotPayload] = []
    func append(_ payload: ProviderSnapshotPayload) { self.lock.withLock { self.payloads.append(payload) } }
    var last: ProviderSnapshotPayload? { self.lock.withLock { self.payloads.last } }
}

@Test func `reconcile adds enabled providers and removes disabled providers`() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("config.json")
    let configStore = CodexBarConfigStore(fileURL: url)
    try configStore.save(CodexBarConfig(providers: [
        ProviderConfig(id: .claude, enabled: true),
        ProviderConfig(id: .cursor, enabled: false),
    ]))
    let recorder = PayloadRecorder()
    let store = LinuxUsageStore(configStore: configStore, onSnapshot: recorder.append)
    try configStore.save(CodexBarConfig(providers: [
        ProviderConfig(id: .claude, enabled: false),
        ProviderConfig(id: .cursor, enabled: true),
    ]))
    store.reconcileProviders(refresh: false)
    let ids = recorder.last?.providers.map(\.id) ?? []
    #expect(ids.contains("cursor"))
    #expect(!ids.contains("claude"))
}
