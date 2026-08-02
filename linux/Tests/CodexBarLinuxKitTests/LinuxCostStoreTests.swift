import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private actor DelayedCostLoader {
    private var continuations: [ProviderSourceMode: CheckedContinuation<CostUsageTokenSnapshot, Never>] = [:]

    func load(config: ProviderConfig) async -> CostUsageTokenSnapshot {
        await withCheckedContinuation { continuation in
            self.continuations[config.source ?? .auto] = continuation
        }
    }

    func finish(_ source: ProviderSourceMode, cost: Double) {
        self.continuations.removeValue(forKey: source)?.resume(returning: CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: cost,
            last30DaysTokens: nil,
            last30DaysCostUSD: cost,
            daily: [],
            updatedAt: Date(timeIntervalSince1970: cost)))
    }

    func hasRequest(for source: ProviderSourceMode) -> Bool {
        self.continuations[source] != nil
    }
}

@Test
func `cost store discards a stale generation after provider configuration changes`() async throws {
    // Given
    let loader = DelayedCostLoader()
    let store = LinuxCostStore(load: { _, config, _ in
        await loader.load(config: config)
    })
    let requestA = ProviderConfig(id: .codex, enabled: true, source: .api)
    let requestB = ProviderConfig(id: .codex, enabled: true, source: .cli)

    // When
    async let first: Void = store.refresh(providerID: "codex", config: requestA)
    while !(await loader.hasRequest(for: .api)) {
        await Task.yield()
    }
    async let second: Void = store.refresh(providerID: "codex", config: requestB)
    while !(await loader.hasRequest(for: .cli)) {
        await Task.yield()
    }
    await loader.finish(.cli, cost: 2)
    await loader.finish(.api, cost: 1)
    await first
    await second

    // Then
    #expect(store.state(providerID: "codex") == .available(try #require(store.view(providerID: "codex"))))
    #expect(store.view(providerID: "codex")?.sessionCostUSD == 2)
}

@Test
func `provider cost view preserves local estimate data through JSON`() throws {
    // Given
    let daily = CostUsageDailyReport.Entry(
        date: "2026-08-02",
        inputTokens: 10,
        outputTokens: 20,
        totalTokens: 30,
        costUSD: 0.5,
        modelsUsed: ["fixture"],
        modelBreakdowns: nil)
    let source = CostUsageProjectSourceBreakdown(
        name: "fixture source",
        path: nil,
        totalTokens: 30,
        totalCostUSD: 0.5,
        daily: [daily],
        modelBreakdowns: nil)
    let project = CostUsageProjectBreakdown(
        name: "fixture project",
        path: nil,
        totalTokens: 30,
        totalCostUSD: 0.5,
        daily: [daily],
        modelBreakdowns: nil,
        sources: [source])
    let session = CostUsageSessionBreakdown(
        sessionID: "fixture-session",
        lastActivity: Date(timeIntervalSince1970: 1),
        inputTokens: 10,
        cachedInputTokens: nil,
        outputTokens: 20,
        totalTokens: 30,
        requestCount: 1,
        costUSD: 0.5,
        modelBreakdowns: [])
    let view = ProviderCostView(
        providerID: "codex",
        sessionCostUSD: 0.5,
        last30DaysCostUSD: 0.5,
        currencyCode: "USD",
        historyDays: 30,
        daily: [daily],
        projects: [project],
        sessions: [session],
        updatedAt: Date(timeIntervalSince1970: 1),
        source: "Local estimate")

    // When
    let decoded = try JSONDecoder().decode(ProviderCostView.self, from: JSONEncoder().encode(view))

    // Then
    #expect(decoded == view)
}
