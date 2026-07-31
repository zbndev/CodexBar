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
