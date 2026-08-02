import Foundation
import Testing

@testable import CodexBarLinuxKit

private struct HistoryFixture {
    let directory: URL
    let day0: Date
    let day1: Date
    let day90: Date
    let reset: Date
    let nextReset: Date

    init() throws {
        self.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        self.day90 = Date(timeIntervalSince1970: 90 * 86_400)
        self.day0 = Date(timeIntervalSince1970: 1)
        self.day1 = Date(timeIntervalSince1970: 86_400)
        self.reset = Date(timeIntervalSince1970: 3 * 86_400)
        self.nextReset = Date(timeIntervalSince1970: 10 * 86_400)
    }
}

@Test
func `history keeps ninety days and starts a new segment after reset`() throws {
    // Given
    let fixture = try HistoryFixture()
    let store = try LinuxPlanHistoryStore(directoryURL: fixture.directory, now: { fixture.day90 })

    // When
    try store.record(providerID: "codex", windowID: "session", point: .init(
        capturedAt: fixture.day0.addingTimeInterval(-1),
        usedPercent: 40,
        resetsAt: fixture.reset))
    try store.record(providerID: "codex", windowID: "session", point: .init(
        capturedAt: fixture.day0,
        usedPercent: 80,
        resetsAt: fixture.reset))
    try store.record(providerID: "codex", windowID: "session", point: .init(
        capturedAt: fixture.day1,
        usedPercent: 5,
        resetsAt: fixture.nextReset))
    let history = try store.load(providerID: "codex", windowID: "session")

    // Then
    #expect(history.segments.count == 2)
    #expect(history.segments.flatMap(\.points).allSatisfy {
        fixture.day90.timeIntervalSince($0.capturedAt) <= 90 * 86_400
    })
    let attributes = try FileManager.default.attributesOfItem(
        atPath: fixture.directory.appendingPathComponent("codex.json").path)
    #expect(attributes[.posixPermissions] as? Int == 0o600)
}
