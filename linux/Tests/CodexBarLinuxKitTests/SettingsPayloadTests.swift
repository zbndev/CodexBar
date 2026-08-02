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
            case let .field(key, _, _, _, _, _): key
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

@Test func `replacing token accounts persists the account list and active index`() throws {
    let (configStore, settingsStore) = tempStores()
    let coordinator = SettingsCoordinator(
        configStore: configStore, settingsStore: settingsStore, onChange: {})
    let account = ProviderTokenAccount(
        id: UUID(), label: "Work", token: "secret", addedAt: 0, lastUsed: nil,
        usageScope: "team", organizationID: "org-1", workspaceID: "workspace-1")
    let data = ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0)
    try coordinator.replaceTokenAccounts(providerID: "zai", data: data)
    let stored = try configStore.load()?.providers
        .first { $0.id == .zai }?.tokenAccounts
    #expect(stored?.accounts.count == 1)
    #expect(stored?.accounts.first?.label == "Work")
    #expect(stored?.accounts.first?.usageScope == "team")
    #expect(stored?.accounts.first?.organizationID == "org-1")
    #expect(stored?.accounts.first?.workspaceID == "workspace-1")
    #expect(stored?.activeIndex == 0)
}

@Test func `clearing provider quota warnings restores inheritance`() throws {
    let (configStore, settingsStore) = tempStores()
    let coordinator = SettingsCoordinator(
        configStore: configStore, settingsStore: settingsStore, onChange: {})
    let warnings = QuotaWarningConfig(
        session: QuotaWarningWindowConfig(thresholds: [60, 25], enabled: true),
        weekly: nil)
    try coordinator.updateQuotaWarnings(providerID: "claude", config: warnings)
    try coordinator.updateQuotaWarnings(providerID: "claude", config: nil)
    let stored = try configStore.load()?.providers
        .first { $0.id == .claude }?.quotaWarnings
    #expect(stored == nil)
}

@Test func `saving hooks persists the complete rules array`() throws {
    let (configStore, settingsStore) = tempStores()
    let coordinator = SettingsCoordinator(
        configStore: configStore, settingsStore: settingsStore, onChange: {})
    let rule = HookRule(event: .refreshFailed, executable: "/bin/true")
    try coordinator.applyHooks(HooksConfig(enabled: true, events: [rule]))
    let hooks = try configStore.load()?.hooks
    #expect(hooks?.enabled == true)
    #expect(hooks?.events.count == 1)
    #expect(hooks?.events.first?.executable == "/bin/true")
}

// MARK: - M5.7 history charts and spend dashboard

private func fixtureCostView() -> ProviderCostView {
    let daily = CostUsageDailyReport.Entry(
        date: "2026-08-01",
        inputTokens: 100,
        outputTokens: 200,
        totalTokens: 300,
        requestCount: 3,
        costUSD: 1.25,
        modelsUsed: ["fixture-model"],
        modelBreakdowns: nil)
    let project = CostUsageProjectBreakdown(
        name: "fixture project",
        path: "/home/fixture/project",
        totalTokens: 300,
        totalCostUSD: 1.25,
        daily: [daily],
        modelBreakdowns: nil,
        sources: [])
    let session = CostUsageSessionBreakdown(
        sessionID: "fixture-session-id",
        lastActivity: Date(timeIntervalSince1970: 1),
        inputTokens: 100,
        cachedInputTokens: nil,
        outputTokens: 200,
        totalTokens: 300,
        requestCount: 3,
        costUSD: 1.25,
        modelBreakdowns: [])
    return ProviderCostView(
        providerID: "codex",
        sessionCostUSD: 0.5,
        last30DaysCostUSD: 1.25,
        currencyCode: "USD",
        historyDays: 30,
        daily: [daily],
        projects: [project],
        sessions: [session],
        updatedAt: Date(timeIntervalSince1970: 1),
        source: "Local estimate")
}

@Test func `settings payloads carrying cost views round-trip through JSON`() throws {
    let payload = SettingsPayload(
        generatedAt: Date(timeIntervalSince1970: 0),
        settings: LinuxSettings(),
        general: [],
        providers: [],
        hooks: HooksConfig(),
        costs: [fixtureCostView()],
        localization: LocalizationCatalog.load(locale: "en"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(SettingsPayload.self, from: encoder.encode(payload)) == payload)
}

@Test func `the settings payload carries the available cost views for the spend pane`() throws {
    let (configStore, settingsStore) = tempStores()
    let costView = fixtureCostView()
    let coordinator = SettingsCoordinator(
        configStore: configStore,
        settingsStore: settingsStore,
        costViews: { [costView] },
        onChange: {})
    let payload = coordinator.payload()
    #expect(payload.costs == [costView])
    #expect(payload.costs.first?.daily.isEmpty == false)
}

@Test func `identity hiding strips cost breakdowns from the settings payload`() throws {
    let (configStore, settingsStore) = tempStores()
    var settings = LinuxSettings()
    settings.hidePersonalInfo = true
    try settingsStore.save(settings)
    let coordinator = SettingsCoordinator(
        configStore: configStore,
        settingsStore: settingsStore,
        costViews: { [fixtureCostView()] },
        onChange: {})
    let cost = try #require(coordinator.payload().costs.first)
    #expect(cost.projects.isEmpty)
    #expect(cost.sessions.isEmpty)
    #expect(!cost.daily.isEmpty)
}

@Test func `the spend pane offers the live dashboard instead of the placeholder`() throws {
    let panes = GeneralPaneCatalog.panes(settings: LinuxSettings(), hooks: HooksConfig())
    let spend = try #require(panes.first { $0.id == "spend" })
    #expect(spend.rows.contains(.spendDashboard))
    #expect(!spend.rows.contains { row in
        if case .info(_, let value) = row { return value.contains("Arrives") }
        return false
    })
}

// MARK: - M5.16 opt-in preference rows

private func editableRowKeys(_ settings: LinuxSettings, paneID: String? = nil) -> [String] {
    GeneralPaneCatalog.panes(settings: settings, hooks: HooksConfig())
        .filter { paneID == nil || $0.id == paneID }
        .flatMap { pane in
            pane.rows.compactMap { row -> String? in
                switch row {
                case let .toggle(key, _, _): key
                case let .picker(key, _, _, _, _): key
                case let .field(key, _, _, _, _, _): key
                default: nil
                }
            }
        }
}

@Test func `the cost estimate toggle lives in the spend pane`() {
    #expect(editableRowKeys(LinuxSettings(), paneID: "spend").contains("costUsageEnabled"))
}

@Test func `the agent sessions toggle lives in the advanced pane`() {
    #expect(editableRowKeys(LinuxSettings(), paneID: "advanced").contains("agentSessionsEnabled"))
}

@Test func `the file-only session row is hidden while agent sessions are off`() {
    var off = LinuxSettings()
    off.agentSessionsEnabled = false
    var on = LinuxSettings()
    on.agentSessionsEnabled = true

    #expect(!editableRowKeys(off, paneID: "advanced").contains("includeFileOnlySessions"))
    #expect(editableRowKeys(on, paneID: "advanced").contains("includeFileOnlySessions"))
}

@Test func `no settings key is offered by two different rows`() {
    let keys = editableRowKeys(LinuxSettings())
    let duplicates = Dictionary(grouping: keys, by: { $0 })
        .filter { $0.value.count > 1 }
        .keys
        .sorted()
    #expect(duplicates.isEmpty, "duplicated row keys: \(duplicates)")
}
