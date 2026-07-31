import Foundation
import Testing

@testable import CodexBarLinuxKit

private func tempFile(_ name: String = "settings.json") -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent(name)
}

@Test func `a missing file loads as defaults`() {
    let store = LinuxSettingsStore(fileURL: tempFile())
    #expect(store.load() == LinuxSettings())
}

@Test func `settings round-trip through the store`() throws {
    let url = tempFile()
    let store = LinuxSettingsStore(fileURL: url)
    var settings = LinuxSettings()
    settings.refreshInterval = .fifteenMinutes
    settings.usageBarsShowUsed = false
    settings.language = "ru"
    try store.save(settings)
    #expect(store.load() == settings)
}

@Test func `saved files are readable only by the owner`() throws {
    let url = tempFile()
    try LinuxSettingsStore(fileURL: url).save(LinuxSettings())
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attributes[.posixPermissions] as? Int) == 0o600)
}

@Test func `partial JSON decodes with defaults for the missing keys`() throws {
    let url = tempFile()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try #"{"language":"ja","hidePersonalInfo":true}"#.write(to: url, atomically: true, encoding: .utf8)
    let loaded = LinuxSettingsStore(fileURL: url).load()
    #expect(loaded.language == "ja")
    #expect(loaded.hidePersonalInfo)
    #expect(loaded.refreshInterval == LinuxSettings().refreshInterval)
}

@Test func `unknown keys are ignored so forward syncs never break decoding`() throws {
    let url = tempFile()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try #"{"fromTheFuture":42,"language":"de"}"#.write(to: url, atomically: true, encoding: .utf8)
    #expect(LinuxSettingsStore(fileURL: url).load().language == "de")
}

@Test func `corrupt JSON loads as defaults rather than crashing`() throws {
    let url = tempFile()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "not json".write(to: url, atomically: true, encoding: .utf8)
    #expect(LinuxSettingsStore(fileURL: url).load() == LinuxSettings())
}

@Test func `XDG_CONFIG_HOME wins over the home directory default`() {
    let url = LinuxSettingsStore.defaultURL(
        environment: ["XDG_CONFIG_HOME": "/tmp/xdg-test"],
        home: URL(fileURLWithPath: "/home/nobody"))
    #expect(url.path == "/tmp/xdg-test/codexbar/linux-settings.json")
}

@Test func `CODEXBAR_CONFIG puts the settings file next to the config`() {
    let url = LinuxSettingsStore.defaultURL(
        environment: ["CODEXBAR_CONFIG": "/tmp/custom/config.json"],
        home: URL(fileURLWithPath: "/home/nobody"))
    #expect(url.path == "/tmp/custom/linux-settings.json")
}

@Test func `an existing legacy config keeps linux settings beside it`() throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let legacyConfig = home.appendingPathComponent(".codexbar/config.json")
    try FileManager.default.createDirectory(
        at: legacyConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: legacyConfig)
    let url = LinuxSettingsStore.defaultURL(
        environment: [:], home: home, fileManager: .default)
    #expect(url.path == home.appendingPathComponent(".codexbar/linux-settings.json").path)
}

@Test func `refresh intervals carry their durations`() {
    #expect(RefreshInterval.manual.seconds == nil)
    #expect(RefreshInterval.fiveMinutes.seconds == 300)
    #expect(RefreshInterval.thirtyMinutes.seconds == 1800)
}
