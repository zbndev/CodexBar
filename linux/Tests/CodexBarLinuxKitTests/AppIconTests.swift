import Foundation
import Testing

@testable import CodexBarLinuxKit

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func writeAsset(_ url: URL, bytes: String) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(bytes.utf8).write(to: url)
}

@Test func `the tray icon is materialised under the name the tray asks for`() throws {
    let root = tempDirectory()
    let cache = tempDirectory()
    try writeAsset(root.appendingPathComponent("docs/icon.png"), bytes: "alpha-icon")

    let path = try #require(AppIcon.placement(checkoutRoot: root, cacheDirectory: cache).themePath)

    #expect(path == cache.path)
    let materialised = cache.appendingPathComponent("\(AppIcon.name).png")
    #expect(FileManager.default.fileExists(atPath: materialised.path))
    #expect(try String(contentsOf: materialised, encoding: .utf8) == "alpha-icon")
}

@Test func `the alpha asset wins over the opaque one`() throws {
    let root = tempDirectory()
    let cache = tempDirectory()
    try writeAsset(root.appendingPathComponent("docs/icon.png"), bytes: "alpha-icon")
    try writeAsset(root.appendingPathComponent("Icon.icon/Assets/codexbar.png"), bytes: "opaque-icon")

    _ = AppIcon.placement(checkoutRoot: root, cacheDirectory: cache).themePath

    let materialised = cache.appendingPathComponent("\(AppIcon.name).png")
    #expect(try String(contentsOf: materialised, encoding: .utf8) == "alpha-icon")
}

@Test func `the opaque asset is used when the alpha one is absent`() throws {
    let root = tempDirectory()
    let cache = tempDirectory()
    try writeAsset(root.appendingPathComponent("Icon.icon/Assets/codexbar.png"), bytes: "opaque-icon")

    _ = AppIcon.placement(checkoutRoot: root, cacheDirectory: cache).themePath

    let materialised = cache.appendingPathComponent("\(AppIcon.name).png")
    #expect(try String(contentsOf: materialised, encoding: .utf8) == "opaque-icon")
}

@Test func `a missing asset yields no theme path rather than an empty directory`() {
    let root = tempDirectory()
    let cache = tempDirectory()

    #expect(AppIcon.placement(checkoutRoot: root, cacheDirectory: cache).themePath == nil)
    #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent("\(AppIcon.name).png").path))
}

@Test func `a redrawn upstream icon replaces the materialised copy`() throws {
    let root = tempDirectory()
    let cache = tempDirectory()
    let source = root.appendingPathComponent("docs/icon.png")
    try writeAsset(source, bytes: "first-icon")
    _ = AppIcon.placement(checkoutRoot: root, cacheDirectory: cache).themePath

    try writeAsset(source, bytes: "redrawn-icon-with-a-different-length")
    _ = AppIcon.placement(checkoutRoot: root, cacheDirectory: cache).themePath

    let materialised = cache.appendingPathComponent("\(AppIcon.name).png")
    #expect(try String(contentsOf: materialised, encoding: .utf8) == "redrawn-icon-with-a-different-length")
}

@Test func `an installed layout uses the icon theme instead of a search path`() throws {
    let installed = tempDirectory()
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)

    let placement = AppIcon.placement(installedRoot: installed, cacheDirectory: tempDirectory())

    #expect(placement.name == AppIcon.name)
    #expect(placement.themePath == nil)
}

@Test func `no asset anywhere falls back to a stock name`() {
    let placement = AppIcon.placement(
        checkoutRoot: tempDirectory(),
        cacheDirectory: tempDirectory())

    #expect(placement.name == AppIcon.fallbackName)
    #expect(placement.themePath == nil)
}

@Test func `the repository ships an asset the tray can actually use`() throws {
    // Guards the paths in `checkoutCandidates` against an upstream move: they are
    // strings, so nothing else would notice until the tray fell back to stock.
    let cache = tempDirectory()
    let path = try #require(AppIcon.placement(cacheDirectory: cache).themePath)
    let materialised = URL(fileURLWithPath: path).appendingPathComponent("\(AppIcon.name).png")
    let data = try Data(contentsOf: materialised)
    #expect(data.count > 1024)
    #expect(data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
}
