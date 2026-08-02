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

private actor CostScanRecorder {
    private var requests: [CostUsageLoadRequest] = []
    private var waiter: CheckedContinuation<CostUsageLoadRequest, Never>?

    func load(_ request: CostUsageLoadRequest) -> CostUsageTokenSnapshot {
        self.requests.append(request)
        self.waiter?.resume(returning: request)
        self.waiter = nil
        return CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            daily: [],
            updatedAt: Date(timeIntervalSince1970: 1))
    }

    func next() async -> CostUsageLoadRequest {
        if let request = self.requests.last { return request }
        return await withCheckedContinuation { continuation in
            self.waiter = continuation
        }
    }
}

private actor UsageTransitionRecorder {
    private var transitions: [[UsageTransition]] = []
    private var waiter: CheckedContinuation<[UsageTransition], Never>?

    func append(_ transitions: [UsageTransition]) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: transitions)
        } else {
            self.transitions.append(transitions)
        }
    }

    func next() async -> [UsageTransition] {
        if !self.transitions.isEmpty { return self.transitions.removeFirst() }
        return await withCheckedContinuation { continuation in
            self.waiter = continuation
        }
    }
}

private actor UsageOutcomeSequence {
    private var outcomes: [ProviderFetchOutcome]

    init(_ outcomes: [ProviderFetchOutcome]) {
        self.outcomes = outcomes
    }

    func next() -> ProviderFetchOutcome {
        self.outcomes.removeFirst()
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

@Test func `enabled refresh starts one automatic thirty day cost scan`() async throws {
    // Given
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let configStore = CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
    try configStore.save(CodexBarConfig(providers: [ProviderConfig(id: .codex, enabled: true)]))
    let scans = CostScanRecorder()
    let costStore = LinuxCostStore(load: { request in
        await scans.load(request)
    })
    let usage = UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date(timeIntervalSince1970: 1))
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
        costStore: costStore,
        fetch: { _, _, _, _ in outcome },
        onSnapshot: { _ in })

    // When
    store.refresh(providerID: "codex")
    let request = await scans.next()

    // Then
    #expect(request.provider == .codex)
    #expect(request.historyDays == 30)
    #expect(!request.forceRefresh)
}

@Test func `refresh records flow through the shared transition engine`() async throws {
    // Given
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let configStore = CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
    try configStore.save(CodexBarConfig(providers: [ProviderConfig(id: .claude, enabled: true)]))
    let outcomes = UsageOutcomeSequence([
        transitionOutcome(remainingPercent: 21),
        transitionOutcome(remainingPercent: 19),
    ])
    let transitions = UsageTransitionRecorder()
    let store = LinuxUsageStore(
        configStore: configStore,
        fetch: { _, _, _, _ in await outcomes.next() },
        onUsageTransitions: { _, values in Task { await transitions.append(values) } },
        onSnapshot: { _ in })

    // When
    store.refresh(providerID: "claude")
    _ = await transitions.next()
    store.refresh(providerID: "claude")
    let values = await transitions.next()

    // Then
    #expect(values == [.quotaLow(windowID: "primary", threshold: 20, remainingPercent: 19)])
}

private func transitionOutcome(remainingPercent: Double) -> ProviderFetchOutcome {
    let usage = UsageSnapshot(
        primary: RateWindow(
            usedPercent: 100 - remainingPercent,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil),
        secondary: nil,
        updatedAt: Date(timeIntervalSince1970: 1))
    return ProviderFetchOutcome(
        result: .success(ProviderFetchResult(
            usage: usage,
            credits: nil,
            dashboard: nil,
            sourceLabel: "Fixture",
            strategyID: "fixture",
            strategyKind: .localProbe)),
        attempts: [])
}
