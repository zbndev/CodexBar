import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private final class CacheClearRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var costCalls = 0
    private var cookieCalls = 0

    func clearCost() async -> CacheClearResult {
        self.lock.withLock { self.costCalls += 1 }
        return CacheClearResult(clearedCount: 1, failedCount: 0)
    }

    func clearCookies() -> CacheClearResult {
        self.lock.withLock { self.cookieCalls += 1 }
        return CacheClearResult(clearedCount: 2, failedCount: 0)
    }

    var calls: (cost: Int, cookies: Int) {
        self.lock.withLock { (self.costCalls, self.cookieCalls) }
    }
}

@Test func `cache actions call only their scoped Core operation and storage remains advisory`() async throws {
    // Given
    let recorder = CacheClearRecorder()
    let controller = LinuxCacheController(
        clearCostCache: recorder.clearCost,
        clearCookieCache: recorder.clearCookies)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cache = root.appendingPathComponent("cache", isDirectory: true)
    let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try Data("abc".utf8).write(to: cache.appendingPathComponent("local.bin"))
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try Data("outside-data".utf8).write(to: outside.appendingPathComponent("private.bin"))
    try FileManager.default.createSymbolicLink(
        at: root.appendingPathComponent("outside-link"),
        withDestinationURL: outside)

    // When
    _ = await controller.clearCostCache()
    _ = controller.clearCookieCache()
    let footprints = controller.refreshStorageFootprints([
        LinuxStorageScanRequest(provider: .codex, paths: [root.path]),
    ])
    let text = String(decoding: try JSONEncoder().encode(footprints), as: UTF8.self)

    // Then
    #expect(recorder.calls.cost == 1)
    #expect(recorder.calls.cookies == 1)
    #expect(FileManager.default.fileExists(atPath: root.path))
    #expect(footprints.footprints == [LinuxStorageFootprint(
        providerID: "codex",
        totalBytes: 3,
        recommendations: [StorageRecommendation(
            title: "Manual cleanup: cache",
            consequence: "Clearing removes provider-owned cached data.")])])
    #expect(!text.contains(root.path))
    #expect(!text.contains(outside.path))
    #expect(!text.lowercased().contains("delete"))
}
