import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `a refresh command round-trips through JSON`() throws {
    let original = BridgeCommand.refresh(provider: "codex")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(BridgeCommand.self, from: data)
    #expect(decoded == original)
}

@Test func `a refresh command with no provider round-trips`() throws {
    let original = BridgeCommand.refresh(provider: nil)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(BridgeCommand.self, from: data)
    #expect(decoded == original)
}

@Test func `Kilo organization commands round-trip through JSON`() throws {
    let commands: [BridgeCommand] = [
        .refreshKiloOrganizations,
        .setKiloOrganizationEnabled(id: "fixture-org", enabled: true),
        .refreshClaudeSwap,
        .switchClaudeSwapAccount(number: 2),
    ]
    for command in commands {
        #expect(try JSONDecoder().decode(
            BridgeCommand.self,
            from: JSONEncoder().encode(command)) == command)
    }
}

@Test func `Kilo organization payload round-trips through JSON`() throws {
    let view = ProviderView(
        id: "kilo:org:fixture-org",
        displayName: "Kilo — Fixture Organization",
        iconResourceName: "kilo",
        accentColorHex: "#000000",
        enabled: true)
    let payload = KiloOrganizationsPayload(
        organizations: [KiloOrganization(id: "fixture-org", name: "Fixture Organization", role: "admin")],
        enabledIDs: ["fixture-org"],
        scopes: [KiloScopeView(
            id: "org:fixture-org",
            title: "Fixture Organization",
            view: view,
            errorMessage: nil)],
        isRefreshing: false,
        errorMessage: nil)
    #expect(try JSONDecoder().decode(
        KiloOrganizationsPayload.self,
        from: JSONEncoder().encode(payload)) == payload)
}

@Test func `claude-swap payload round-trips through JSON`() throws {
    let payload = ClaudeSwapPayload(
        executablePath: "fixture-executable",
        accounts: [CodexBarLinuxKit.ClaudeSwapAccountRow(
            number: 2,
            email: "fixture-account@example.test",
            isActive: true,
            status: "Ready")],
        errorMessage: nil)
    #expect(try JSONDecoder().decode(
        ClaudeSwapPayload.self,
        from: JSONEncoder().encode(payload)) == payload)
}

@Test func `commands decode from the wire format the web UI sends`() throws {
    let json = #"{"type":"selectProvider","id":"claude"}"#
    let decoded = try JSONDecoder().decode(BridgeCommand.self, from: Data(json.utf8))
    #expect(decoded == .selectProvider(id: "claude"))
}

@Test func `an unknown command type decodes as a decoding error rather than crashing`() {
    let json = #"{"type":"somethingNobodyImplemented"}"#
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(BridgeCommand.self, from: Data(json.utf8))
    }
}

@Test func `an error event encodes with its message`() throws {
    let data = try JSONEncoder().encode(BridgeEvent.error(message: "boom"))
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"error\""))
    #expect(text.contains("boom"))
}

@Test func `event JSON embedded in a script literal escapes quotes and backslashes`() {
    let escaped = BridgeScriptEncoding.javaScriptStringLiteral(#"{"a":"b\c"}"#)
    #expect(escaped == #""{\"a\":\"b\\c\"}""#)
}

@Test func `an update-provider-config command round-trips`() throws {
    var patch = ProviderConfigPatch()
    patch.enabled = true
    patch.apiKey = "sk"
    let original = BridgeCommand.updateProviderConfig(id: "claude", patch: patch)
    let decoded = try JSONDecoder().decode(
        BridgeCommand.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}

@Test func `a settings event round-trips`() throws {
    let payload = SettingsPayload(
        generatedAt: Date(timeIntervalSince1970: 0),
        settings: LinuxSettings(),
        general: [],
        providers: [],
        claudeSwap: ClaudeSwapPayload(executablePath: nil, accounts: [], errorMessage: nil),
        hooks: HooksConfig(),
        localization: LocalizationCatalog.load(locale: "en"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(
        BridgeEvent.self, from: encoder.encode(BridgeEvent.settings(payload)))
    #expect(decoded == .settings(payload))
}

@Test func `an update-hooks command round-trips`() throws {
    let original = BridgeCommand.updateHooks(HooksConfig(enabled: true, events: []))
    let decoded = try JSONDecoder().decode(
        BridgeCommand.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}

@Test func `open-config-folder command round-trips`() throws {
    let original = BridgeCommand.openConfigFolder
    let decoded = try JSONDecoder().decode(
        BridgeCommand.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}

@Test func `replace-token-accounts command round-trips`() throws {
    let account = ProviderTokenAccount(
        id: UUID(), label: "Work", token: "secret", addedAt: 0, lastUsed: nil,
        usageScope: "team", organizationID: "org-1", workspaceID: "workspace-1")
    let data = ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0)
    let original = BridgeCommand.replaceTokenAccounts(providerID: "zai", data: data)
    let decoded = try JSONDecoder().decode(
        BridgeCommand.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}

@Test func `provider quota-warning command round-trips`() throws {
    let config = QuotaWarningConfig(
        session: QuotaWarningWindowConfig(thresholds: [50, 20], enabled: true),
        weekly: nil)
    let original = BridgeCommand.updateQuotaWarnings(providerID: "claude", config: config)
    let decoded = try JSONDecoder().decode(
        BridgeCommand.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}

@Test func `clearing a quota-warning override round-trips as an absent config`() throws {
    let original = BridgeCommand.updateQuotaWarnings(providerID: "claude", config: nil)
    let decoded = try JSONDecoder().decode(
        BridgeCommand.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}

@Test func `linux settings map onto popup display preferences`() {
    var settings = LinuxSettings()
    settings.usageBarsShowUsed = false
    settings.resetTimesShowAbsolute = true
    settings.showCreditsAndExtraUsage = false
    settings.hidePersonalInfo = true
    let display = DisplayPreferences(settings: settings)
    #expect(!display.usageBarsShowUsed)
    #expect(display.resetTimesShowAbsolute)
    #expect(!display.showCreditsAndExtraUsage)
    #expect(display.hidePersonalInfo)
}

@Test func `snapshot display preferences round-trip through JSON`() throws {
    let original = ProviderSnapshotPayload(
        generatedAt: Date(timeIntervalSince1970: 0),
        providers: [],
        display: DisplayPreferences(settings: LinuxSettings()))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(
        ProviderSnapshotPayload.self,
        from: encoder.encode(original)) == original)
}

@Test func `start login and cancel login commands round trip`() throws {
    let start = BridgeCommand.startLogin(provider: "claude")
    let data = try JSONEncoder().encode(start)
    #expect(String(decoding: data, as: UTF8.self).contains("\"startLogin\""))
    #expect(try JSONDecoder().decode(BridgeCommand.self, from: data) == start)

    let cancel = BridgeCommand.cancelLogin(provider: "claude")
    let cancelData = try JSONEncoder().encode(cancel)
    #expect(try JSONDecoder().decode(BridgeCommand.self, from: cancelData) == cancel)
}

@Test func `managed Codex account commands round-trip through JSON`() throws {
    let id = UUID()
    let commands: [BridgeCommand] = [
        .addManagedCodexAccount,
        .reauthenticateManagedCodexAccount(id: id),
        .removeManagedCodexAccount(id: id),
        .selectManagedCodexAccount(id: id),
        .selectManagedCodexAccount(id: nil),
    ]
    for command in commands {
        #expect(try JSONDecoder().decode(
            BridgeCommand.self,
            from: JSONEncoder().encode(command)) == command)
    }
}

@Test func `managed Codex account views round-trip inside settings payloads`() throws {
    let account = ManagedCodexAccountView(
        id: UUID(), email: "managed@example.test", workspaceLabel: "Fixture workspace", isActive: true)
    let payload = SettingsPayload(
        generatedAt: Date(timeIntervalSince1970: 0),
        settings: LinuxSettings(),
        general: [],
        providers: [],
        managedCodexAccounts: [account],
        hooks: HooksConfig(),
        localization: LocalizationCatalog.load(locale: "en"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(SettingsPayload.self, from: encoder.encode(payload)) == payload)
}

@Test func `the login progress event round trips`() throws {
    let event = BridgeEvent.loginProgress(
        provider: "copilot",
        phase: LoginPhasePayload(.showingDeviceCode(
            code: "ABCD-1234", url: "https://github.com/login/device")))
    let data = try JSONEncoder().encode(event)
    #expect(String(decoding: data, as: UTF8.self).contains("\"loginProgress\""))
    #expect(try JSONDecoder().decode(BridgeEvent.self, from: data) == event)
}

@Test func `external credential login progress round trips`() throws {
    let event = BridgeEvent.loginProgress(
        provider: "vertexai",
        phase: LoginPhasePayload(.waitingForExternalTool(
            command: "gcloud auth application-default login",
            helpURL: "https://docs.cloud.google.com/docs/authentication/application-default-credentials")))
    let data = try JSONEncoder().encode(event)
    #expect(try JSONDecoder().decode(BridgeEvent.self, from: data) == event)
}

@Test func `an undecodable message never echoes its body`() throws {
    // The shape settings.js sends when the user pastes a cookie header, with
    // one field the wrong type so decoding fails.
    let secret = "sessionid=super-secret-value; csrftoken=also-secret"
    let json = """
        {"type":"updateProviderConfig","id":"perplexity",
         "patch":{"cookieHeader":"\(secret)","enabled":"not-a-bool"}}
        """
    var thrown: (any Error)?
    do {
        _ = try JSONDecoder().decode(BridgeCommand.self, from: Data(json.utf8))
        Issue.record("expected the malformed patch to fail decoding")
    } catch {
        thrown = error
    }
    let line = BridgeDiagnostics.undecodableMessage(json: json, error: try #require(thrown))
    #expect(!line.contains(secret))
    #expect(!line.contains("super-secret-value"))
    #expect(!line.contains("cookieHeader"))
    #expect(line.contains("type: updateProviderConfig"))
}

@Test func `a message whose type is not an identifier is reported unnamed`() {
    // Nothing may reach the log by riding in on the type field.
    let line = BridgeDiagnostics.undecodableMessage(
        json: #"{"type":"sessionid=secret-value"}"#,
        error: LoginError.cancelled)
    #expect(line.contains("unnamed"))
    #expect(!line.contains("secret-value"))
}

@Test func `unparseable json is reported unnamed`() {
    let line = BridgeDiagnostics.undecodableMessage(json: "{not json", error: LoginError.cancelled)
    #expect(line.contains("unnamed"))
    #expect(!line.contains("not json"))
}

// MARK: - M5.7 history charts and spend dashboard

/// A cost snapshot with a non-empty daily report plus identity-bearing
/// breakdowns, so the scrubbing tests have something real to strip.
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

/// Two utilization points in one segment — the smallest history the popup
/// chart can draw a line through.
private func fixtureHistory() -> [UtilizationHistorySeries] {
    [UtilizationHistorySeries(windowID: "primary", segments: [
        UtilizationHistorySegment(resetsAt: nil, points: [
            UtilizationHistoryPoint(capturedAt: Date(timeIntervalSince1970: 100), usedPercent: 12.5, resetsAt: nil),
            UtilizationHistoryPoint(capturedAt: Date(timeIntervalSince1970: 200), usedPercent: 25, resetsAt: nil),
        ]),
    ])]
}

private func fixtureProviderWithCostAndHistory() -> ProviderView {
    var provider = ProviderView(
        id: "codex",
        displayName: "Codex",
        iconResourceName: "codex",
        accentColorHex: "#000000",
        enabled: true,
        windows: [ProviderWindowView(id: "primary", title: "Session", usedPercent: 25)])
    provider.cost = fixtureCostView()
    provider.history = fixtureHistory()
    return provider
}

@Test func `a refresh-cost command round-trips through JSON`() throws {
    let original = BridgeCommand.refreshCost(provider: "codex")
    let data = try JSONEncoder().encode(original)
    #expect(String(decoding: data, as: UTF8.self).contains("\"refreshCost\""))
    #expect(try JSONDecoder().decode(BridgeCommand.self, from: data) == original)
}

@Test func `a refresh-cost command decodes from the wire format the web UI sends`() throws {
    let json = #"{"type":"refreshCost","provider":"claude"}"#
    let decoded = try JSONDecoder().decode(BridgeCommand.self, from: Data(json.utf8))
    #expect(decoded == .refreshCost(provider: "claude"))
}

@Test func `a test-hook command and summary payload round-trip through JSON`() throws {
    let command = BridgeCommand.testHook(event: .quotaReached, provider: "claude")
    #expect(try JSONDecoder().decode(
        BridgeCommand.self,
        from: JSONEncoder().encode(command)) == command)

    let payload = HookTestPayload(results: [HookTestRuleSummary(ruleID: "fixture-rule", success: true)])
    #expect(try JSONDecoder().decode(
        BridgeEvent.self,
        from: JSONEncoder().encode(BridgeEvent.hookTest(payload))) == .hookTest(payload))
}

@Test func `a snapshot carrying cost and utilization history round-trips through JSON`() throws {
    let payload = ProviderSnapshotPayload(
        generatedAt: Date(timeIntervalSince1970: 0),
        providers: [fixtureProviderWithCostAndHistory()])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(
        ProviderSnapshotPayload.self,
        from: encoder.encode(payload)) == payload)
}

@Test func `identity hiding strips project paths and session ids from snapshot costs`() throws {
    let payload = ProviderSnapshotPayload(
        generatedAt: Date(timeIntervalSince1970: 0),
        providers: [fixtureProviderWithCostAndHistory()])

    let hidden = payload.hidingPersonalInfo(true)
    let cost = try #require(hidden.providers.first?.cost)
    #expect(cost.projects.isEmpty)
    #expect(cost.sessions.isEmpty)
    // Aggregates survive: the charts need the daily report and the totals.
    #expect(cost.daily.count == 1)
    #expect(cost.sessionCostUSD == 0.5)
    #expect(hidden.providers.first?.history == fixtureHistory())

    #expect(payload.hidingPersonalInfo(false) == payload)
}

@Test func `identity hiding keeps project paths and session ids out of the encoded snapshot`() throws {
    let payload = ProviderSnapshotPayload(
        generatedAt: Date(timeIntervalSince1970: 0),
        providers: [fixtureProviderWithCostAndHistory()])
    let text = String(decoding: try JSONEncoder().encode(payload.hidingPersonalInfo(true)), as: UTF8.self)
    #expect(!text.contains("/home/fixture/project"))
    #expect(!text.contains("fixture-session-id"))
    #expect(text.contains("fixture-model"))
}
