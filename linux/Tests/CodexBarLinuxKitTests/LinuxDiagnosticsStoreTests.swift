import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private enum DiagnosticsFixtureError: LocalizedError {
    case failed

    var errorDescription: String? {
        "token=fake-token-9a3; query=fake-query-7b2; path=/fixture/private/diagnostics"
    }
}

@Test func `diagnostics exports safe categories and retains only the newest one hundred records`() throws {
    // Given
    let store = LinuxDiagnosticsStore()
    let descriptor = ProviderDescriptorRegistry.descriptor(for: .claude)
    let outcome = ProviderFetchOutcome(
        result: .failure(DiagnosticsFixtureError.failed),
        attempts: [ProviderFetchAttempt(
            strategyID: "token=fake-token-9a3?query=fake-query-7b2",
            kind: .oauth,
            wasAvailable: false,
            errorDescription: "token=fake-token-9a3 query=fake-query-7b2 /fixture/private/diagnostics")])

    // When
    for index in 0 ... 100 {
        store.record(.init(
            provider: .claude,
            descriptor: descriptor,
            outcome: outcome,
            sourceMode: .auto,
            settings: nil,
            auth: ProviderDiagnosticAuthSummary(configured: false, modes: ["oauth"]),
            appVersion: "fixture-\(index)"))
    }
    let data = try JSONEncoder().encode(store.payload())
    let text = String(decoding: data, as: UTF8.self)

    // Then
    #expect(store.payload().diagnostics.count == 100)
    #expect(store.payload().diagnostics.first?.appVersion == "fixture-1")
    #expect(text.contains("\"provider\":\"claude\""))
    #expect(text.contains("\"source\":\"failed\""))
    #expect(text.contains("\"wasAvailable\":false"))
    #expect(text.contains("\"errorCategory\":\"auth\""))
    #expect(!text.contains("fake-token-9a3"))
    #expect(!text.contains("fake-query-7b2"))
    #expect(!text.contains("/fixture/private/diagnostics"))
}
