import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private func tempStores() -> (CodexBarConfigStore, LinuxSettingsStore) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    return (
        CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json")),
        LinuxSettingsStore(fileURL: directory.appendingPathComponent("linux-settings.json")))
}

private final class TestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false
    func set() { self.lock.withLock { self.storage = true } }
    var value: Bool { self.lock.withLock { self.storage } }
}

@Test func `the payload carries every enabled provider plus the linux settings`() throws {
    let (configStore, settingsStore) = tempStores()
    let coordinator = SettingsCoordinator(
        configStore: configStore,
        settingsStore: settingsStore,
        onChange: {})
    let payload = coordinator.payload()
    #expect(payload.settings == LinuxSettings())
    #expect(!payload.providers.isEmpty)
    #expect(payload.providers.contains { $0.id == "claude" })
}

@Test func `applying a provider patch persists it to the shared config`() throws {
    let (configStore, settingsStore) = tempStores()
    let coordinator = SettingsCoordinator(
        configStore: configStore,
        settingsStore: settingsStore,
        onChange: {})
    var patch = ProviderConfigPatch()
    patch.enabled = true
    patch.apiKey = "sk-live"
    try coordinator.applyProviderPatch(id: "ollama", patch: patch)

    let reloaded = try configStore.load()
    let ollama = reloaded?.providers.first { $0.id == .ollama }
    #expect(ollama?.enabled == true)
    #expect(ollama?.apiKey == "sk-live")
}

@Test func `a patch for an unknown provider id throws rather than writing nonsense`() throws {
    let (configStore, settingsStore) = tempStores()
    let coordinator = SettingsCoordinator(
        configStore: configStore,
        settingsStore: settingsStore,
        onChange: {})
    #expect(throws: (any Error).self) {
        try coordinator.applyProviderPatch(id: "not-a-provider", patch: ProviderConfigPatch())
    }
}

@Test func `applying settings persists them and fires onChange`() throws {
    let (configStore, settingsStore) = tempStores()
    let fired = TestFlag()
    let coordinator = SettingsCoordinator(
        configStore: configStore,
        settingsStore: settingsStore,
        onChange: { fired.set() })
    var settings = LinuxSettings()
    settings.refreshInterval = .manual
    try coordinator.applySettings(settings)
    #expect(settingsStore.load().refreshInterval == .manual)
    #expect(fired.value)
}

@Test func `an existing provider entry is patched, not duplicated`() throws {
    let (configStore, settingsStore) = tempStores()
    let coordinator = SettingsCoordinator(
        configStore: configStore,
        settingsStore: settingsStore,
        onChange: {})
    var patch = ProviderConfigPatch()
    patch.apiKey = "one"
    try coordinator.applyProviderPatch(id: "claude", patch: patch)
    patch.apiKey = "two"
    try coordinator.applyProviderPatch(id: "claude", patch: patch)
    let reloaded = try configStore.load()
    #expect(reloaded?.providers.filter { $0.id == .claude }.count == 1)
    #expect(reloaded?.providers.first { $0.id == .claude }?.apiKey == "two")
}

@Test func `the payload carries eight normal panes and reveals debug when enabled`() throws {
    let (configStore, settingsStore) = tempStores()
    let coordinator = SettingsCoordinator(
        configStore: configStore,
        settingsStore: settingsStore,
        onChange: {})
    let ids = coordinator.payload().general.map(\.id)
    #expect(ids == [
        "general", "spend", "notifications", "tray", "menu",
        "advanced", "hooks", "about",
    ])
    var settings = LinuxSettings()
    settings.debugMenuEnabled = true
    try settingsStore.save(settings)
    #expect(coordinator.payload().general.map(\.id).last == "debug")
}

@Test func `general pane row keys match LinuxSettings property names`() throws {
    let panes = GeneralPaneCatalog.panes(settings: LinuxSettings(), hooks: HooksConfig())
    let rowKeys = panes.flatMap { pane in
        pane.rows.compactMap { row -> String? in
            switch row {
            case let .toggle(key, _, _): key
            case let .picker(key, _, _, _, _): key
            case let .field(key, _, _, _, _): key
            default: nil
            }
        }
    }
    // Every editable key must be a real CodingKey of LinuxSettings, or the
    // renderer's key-based write-back silently drops the edit.
    let settingsMirror = Mirror(reflecting: LinuxSettings())
    let propertyNames = Set(settingsMirror.children.compactMap(\.label))
    for key in rowKeys where key != "language" && key != "hooksEnabled" {
        #expect(propertyNames.contains(key), "row key \(key) is not a LinuxSettings property")
    }
}

@Test func `the about pane carries a version and links`() {
    let panes = GeneralPaneCatalog.panes(settings: LinuxSettings(), hooks: HooksConfig())
    let about = panes.first { $0.id == "about" }
    #expect(about?.rows.contains { row in
        if case .info(let title, _) = row { return title == "Version" }
        return false
    } == true)
    #expect(about?.rows.contains { row in
        if case .link(_, let url) = row { return url.contains("github.com") }
        return false
    } == true)
}
