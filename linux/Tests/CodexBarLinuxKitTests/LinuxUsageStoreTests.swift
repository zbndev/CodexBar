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

private actor RefreshRecordRecorder {
    private var records: [ProviderRefreshRecord] = []
    private var waiter: CheckedContinuation<ProviderRefreshRecord, Never>?

    func append(_ record: ProviderRefreshRecord) {
        self.records.append(record)
        self.waiter?.resume(returning: record)
        self.waiter = nil
    }

    func next() async -> ProviderRefreshRecord {
        if let record = self.records.last { return record }
        return await withCheckedContinuation { continuation in
            self.waiter = continuation
        }
    }
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

@Test func `reconcile publishes the provider card`() throws {
    // Given
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("config.json")
    let configStore = CodexBarConfigStore(fileURL: url)
    try configStore.save(CodexBarConfig(providers: [
        ProviderConfig(id: .claude, enabled: true),
    ]))
    let recorder = PayloadRecorder()
    let store = LinuxUsageStore(configStore: configStore, onSnapshot: recorder.append)

    // When
    store.reconcileProviders(refresh: false)

    // Then
    #expect(recorder.last?.providers.contains(where: { $0.id == "claude" }) == true)
}

@Test func `successful refresh publishes the provider card before consumers run`() async throws {
    // Given
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let configStore = CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
    try configStore.save(CodexBarConfig(providers: [ProviderConfig(id: .claude, enabled: true)]))
    let payloads = PayloadRecorder()
    let records = RefreshRecordRecorder()
    let usage = UsageSnapshot(
        primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
        secondary: nil,
        updatedAt: Date(timeIntervalSince1970: 1))
    let outcome = ProviderFetchOutcome(
        result: .success(ProviderFetchResult(
            usage: usage,
            credits: nil,
            dashboard: nil,
            sourceLabel: "Fixture",
            strategyID: "fixture",
            strategyKind: .localProbe)),
        attempts: [])
    let store = LinuxUsageStore(
        configStore: configStore,
        historyStore: try LinuxPlanHistoryStore(directoryURL: directory.appendingPathComponent("history")),
        fetch: { _, _, _, _ in outcome },
        onRefreshRecord: { record in
            Task { await records.append(record) }
        },
        onSnapshot: payloads.append)

    // When
    store.refresh(providerID: "claude")
    let record = await records.next()

    // Then
    #expect(record.snapshot?.primary?.usedPercent == usage.primary?.usedPercent)
    #expect(payloads.last?.providers.contains(where: { $0.id == "claude" && $0.errorMessage == nil }) == true)
}
