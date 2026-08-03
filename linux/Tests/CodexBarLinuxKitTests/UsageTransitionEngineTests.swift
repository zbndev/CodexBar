import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private enum TransitionFixtureError: Error {
    case failed
}

@Test func `first observation establishes a quota baseline`() {
    // Given
    let engine = UsageTransitionEngine(lowQuotaThresholds: [20])

    // When
    let transitions = engine.transitions(for: transitionRecord(remainingPercent: 21))

    // Then
    #expect(transitions.isEmpty)
}

@Test func `remaining quota crossing twenty emits quota low once`() {
    // Given
    let engine = UsageTransitionEngine(lowQuotaThresholds: [20])
    _ = engine.transitions(for: transitionRecord(remainingPercent: 21))

    // When
    let transitions = engine.transitions(for: transitionRecord(remainingPercent: 19))

    // Then
    #expect(transitions == [.quotaLow(windowID: "primary", threshold: 20, remainingPercent: 19)])
}

@Test func `repeated low quota observation is silent`() {
    // Given
    let engine = UsageTransitionEngine(lowQuotaThresholds: [20])
    _ = engine.transitions(for: transitionRecord(remainingPercent: 21))
    _ = engine.transitions(for: transitionRecord(remainingPercent: 19))

    // When
    let transitions = engine.transitions(for: transitionRecord(remainingPercent: 19))

    // Then
    #expect(transitions.isEmpty)
}

@Test func `zero remaining quota emits reached once`() {
    // Given
    let engine = UsageTransitionEngine(lowQuotaThresholds: [20])
    _ = engine.transitions(for: transitionRecord(remainingPercent: 19))

    // When
    let reached = engine.transitions(for: transitionRecord(remainingPercent: 0))
    let repeated = engine.transitions(for: transitionRecord(remainingPercent: 0))

    // Then
    #expect(reached == [.quotaReached(windowID: "primary")])
    #expect(repeated.isEmpty)
}

@Test func `changed reset boundary with increased remaining emits reset`() {
    // Given
    let engine = UsageTransitionEngine(lowQuotaThresholds: [20])
    // A whole window later, so the boundary is unambiguously a new cycle rather
    // than the same one re-rounded.
    _ = engine.transitions(for: transitionRecord(
        remainingPercent: 0,
        resetsAt: Date(timeIntervalSince1970: 100)))

    // When
    let transitions = engine.transitions(for: transitionRecord(
        remainingPercent: 80,
        resetsAt: Date(timeIntervalSince1970: 100 + 300 * 60)))

    // Then
    #expect(transitions == [.quotaReset(windowID: "primary", remainingPercent: 80)])
}

@Test func `a quota reset carries the observed remaining rather than a full window`() {
    // Given
    // A 5h lane observed rolling over at 08-04 00:28 held 29% remaining, not
    // 100%: the reset is detected on the first refresh after the boundary, by
    // which point the new cycle has already been drawn down.
    let engine = UsageTransitionEngine(lowQuotaThresholds: [20])
    _ = engine.transitions(for: transitionRecord(
        remainingPercent: 8,
        resetsAt: Date(timeIntervalSince1970: 807_411_000)))

    // When
    let transitions = engine.transitions(for: transitionRecord(
        remainingPercent: 29,
        resetsAt: Date(timeIntervalSince1970: 807_488_400)))

    // Then
    #expect(transitions == [.quotaReset(windowID: "primary", remainingPercent: 29)])
}

@Test func `a minute-rounded reset boundary does not emit a quota reset`() {
    // Given
    // Measured from `~/.config/codexbar/history/claude.json`: the weekly lane
    // re-rounds the same cycle and oscillates between two boundaries exactly
    // 60s apart, while a rolling window's remaining ticks up as old usage falls
    // off its tail. Together those read as a reset on every other refresh.
    let engine = UsageTransitionEngine(lowQuotaThresholds: [20])
    _ = engine.transitions(for: transitionRecord(
        remainingPercent: 43,
        resetsAt: Date(timeIntervalSince1970: 807_785_940),
        windowMinutes: 7 * 24 * 60))

    // When
    let transitions = engine.transitions(for: transitionRecord(
        remainingPercent: 44,
        resetsAt: Date(timeIntervalSince1970: 807_786_000),
        windowMinutes: 7 * 24 * 60))

    // Then
    #expect(transitions.isEmpty)
}

@Test func `failed refresh emits failure without changing quota baseline`() {
    // Given
    let engine = UsageTransitionEngine(lowQuotaThresholds: [20])
    _ = engine.transitions(for: transitionRecord(remainingPercent: 21))

    // When
    let failed = engine.transitions(for: failedTransitionRecord(unavailable: false))
    let lowered = engine.transitions(for: transitionRecord(remainingPercent: 19))

    // Then
    #expect(failed == [.refreshFailed])
    #expect(lowered == [.quotaLow(windowID: "primary", threshold: 20, remainingPercent: 19)])
}

@Test func `provider recovery emits recovered once`() {
    // Given
    let engine = UsageTransitionEngine(lowQuotaThresholds: [20])

    // When
    let unavailable = engine.transitions(for: failedTransitionRecord(unavailable: true))
    let recovered = engine.transitions(for: transitionRecord(remainingPercent: 50))
    let repeated = engine.transitions(for: transitionRecord(remainingPercent: 50))

    // Then
    #expect(unavailable == [.refreshFailed, .providerUnavailable])
    #expect(recovered == [.providerRecovered])
    #expect(repeated.isEmpty)
}

@Test func `a disappeared window drops its prior quota baseline`() {
    // Given
    let engine = UsageTransitionEngine(lowQuotaThresholds: [20])
    _ = engine.transitions(for: transitionRecord(remainingPercent: 21))

    // When
    _ = engine.transitions(for: transitionRecord(remainingPercent: 50, windowID: "secondary"))
    let transitions = engine.transitions(for: transitionRecord(remainingPercent: 19))

    // Then
    #expect(transitions.isEmpty)
}

private func transitionRecord(
    remainingPercent: Double,
    resetsAt: Date? = nil,
    windowID: String = "primary",
    windowMinutes: Int = 300) -> ProviderRefreshRecord
{
    let window = RateWindow(
        usedPercent: 100 - remainingPercent,
        windowMinutes: windowMinutes,
        resetsAt: resetsAt,
        resetDescription: nil)
    let snapshot = UsageSnapshot(
        primary: windowID == "primary" ? window : nil,
        secondary: windowID == "secondary" ? window : nil,
        updatedAt: Date(timeIntervalSince1970: 1))
    let result = ProviderFetchResult(
        usage: snapshot,
        credits: nil,
        dashboard: nil,
        sourceLabel: "Fixture",
        strategyID: "fixture",
        strategyKind: .localProbe)
    return ProviderRefreshRecord(
        view: transitionView(),
        snapshot: snapshot,
        outcome: ProviderFetchOutcome(result: .success(result), attempts: []))
}

private func failedTransitionRecord(unavailable: Bool) -> ProviderRefreshRecord {
    ProviderRefreshRecord(
        view: transitionView(),
        snapshot: nil,
        outcome: ProviderFetchOutcome(
            result: .failure(TransitionFixtureError.failed),
            attempts: [ProviderFetchAttempt(
                strategyID: "fixture",
                kind: .localProbe,
                wasAvailable: !unavailable,
                errorDescription: nil)]))
}

private func transitionView() -> ProviderView {
    ProviderView(
        id: "claude",
        displayName: "Claude",
        iconResourceName: "claude",
        accentColorHex: "#000000",
        enabled: true)
}
