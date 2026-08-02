import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `transitions map to their Core hook event types`() {
    // Given
    let dispatcher = LinuxHookDispatcher(hooksConfig: { HooksConfig() })

    // When
    let events = [
        dispatcher.event(for: .quotaLow(windowID: "primary", threshold: 20, remainingPercent: 19), provider: "claude"),
        dispatcher.event(for: .quotaReached(windowID: "primary"), provider: "claude"),
        dispatcher.event(for: .quotaReset(windowID: "primary"), provider: "claude"),
        dispatcher.event(for: .refreshFailed, provider: "claude"),
        dispatcher.event(for: .providerUnavailable, provider: "claude"),
        dispatcher.event(for: .providerRecovered, provider: "claude"),
    ]

    // Then
    #expect(events.map(\.event) == [
        .quotaLow,
        .quotaReached,
        .quotaReset,
        .refreshFailed,
        .providerUnavailable,
        .providerRecovered,
    ])
}

@Test func `test hook returns only per rule success summaries`() async {
    // Given
    let rule = HookRule(id: "fixture-rule", event: .quotaReached, provider: "claude", executable: "/usr/bin/true")
    let dispatcher = LinuxHookDispatcher(hooksConfig: { HooksConfig(enabled: true, events: [rule]) })

    // When
    let summaries = await dispatcher.testHook(event: .quotaReached, provider: "claude")

    // Then
    #expect(summaries == [HookTestRuleSummary(ruleID: "fixture-rule", success: true)])
}

@Test func `dispatch runs a matching fixture rule through Core`() async throws {
    // Given
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: outputURL) }
    let rule = HookRule(
        id: "fixture-rule",
        event: .quotaReached,
        provider: "claude",
        executable: "/usr/bin/tee",
        arguments: [outputURL.path])
    let dispatcher = LinuxHookDispatcher(hooksConfig: { HooksConfig(enabled: true, events: [rule]) })

    // When
    await dispatcher.dispatch(transitions: [.quotaReached(windowID: "primary")], provider: "claude")

    // Then
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let event = try decoder.decode(HookEvent.self, from: Data(contentsOf: outputURL))
    #expect(event.event == .quotaReached)
    #expect(event.provider == "claude")
}
