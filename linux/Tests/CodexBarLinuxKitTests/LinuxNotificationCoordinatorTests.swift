import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private actor SentNotificationRecorder {
    private var sent: [(summary: String, body: String, urgency: UInt8, sound: Bool)] = []
    private var waiter: CheckedContinuation<(summary: String, body: String, urgency: UInt8, sound: Bool), Never>?

    func append(summary: String, body: String, urgency: UInt8, sound: Bool) {
        let notification = (summary, body, urgency, sound)
        self.sent.append(notification)
        self.waiter?.resume(returning: notification)
        self.waiter = nil
    }

    func values() -> [(summary: String, body: String, urgency: UInt8, sound: Bool)] {
        self.sent
    }

    func next() async -> (summary: String, body: String, urgency: UInt8, sound: Bool) {
        if let notification = self.sent.last { return notification }
        return await withCheckedContinuation { continuation in self.waiter = continuation }
    }
}

private struct RecordingDesktopNotificationSender: DesktopNotificationSending {
    let recorder: SentNotificationRecorder
    let result: Result<Void, NotificationFixtureError>

    init(
        recorder: SentNotificationRecorder,
        result: Result<Void, NotificationFixtureError> = .success(()))
    {
        self.recorder = recorder
        self.result = result
    }

    func send(summary: String, body: String, urgency: UInt8, sound: Bool) async throws {
        try self.result.get()
        await self.recorder.append(summary: summary, body: body, urgency: urgency, sound: sound)
    }
}

private enum NotificationFixtureError: Error {
    case unavailable
}

private actor NotificationTransitionRecorder {
    private var calls = 0
    private var waiter: CheckedContinuation<Void, Never>?

    func append() {
        self.calls += 1
        self.waiter?.resume()
        self.waiter = nil
    }

    func next() async {
        if self.calls > 0 {
            self.calls -= 1
            return
        }
        await withCheckedContinuation { continuation in self.waiter = continuation }
    }
}

private actor NotificationOutcomeSequence {
    private var outcomes: [ProviderFetchOutcome]

    init(_ outcomes: [ProviderFetchOutcome]) {
        self.outcomes = outcomes
    }

    func next() -> ProviderFetchOutcome {
        self.outcomes.removeFirst()
    }
}

@Test func `globally disabled notifications send nothing`() async {
    var settings = LinuxSettings()
    settings.quotaWarningNotificationsEnabled = false
    let recorder = SentNotificationRecorder()
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(recorder: recorder))

    await coordinator.consume(
        [.quotaLow(windowID: "primary", threshold: 20, remainingPercent: 19)],
        provider: notificationProvider(),
        settings: settings)

    #expect(await recorder.values().isEmpty)
}

@Test func `per-window disable suppresses only its own quota warning lane`() async {
    var settings = LinuxSettings()
    settings.quotaWarningSessionEnabled = false
    settings.quotaWarningWeeklyEnabled = true
    let recorder = SentNotificationRecorder()
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(recorder: recorder))

    await coordinator.consume(
        [
            .quotaLow(windowID: "primary", threshold: 20, remainingPercent: 19),
            .quotaLow(windowID: "secondary", threshold: 20, remainingPercent: 19),
        ],
        provider: notificationProvider(),
        settings: settings)

    let sent = await recorder.values()
    #expect(sent.count == 1)
    #expect(sent[0].body == "Claude / secondary / 19% remaining")
}

@Test func `a quota restored notification reports the observed remaining`() async {
    // A reset is detected on the first refresh after the boundary, so the lane
    // is rarely full by then. The body used to claim 100% unconditionally.
    let recorder = SentNotificationRecorder()
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(recorder: recorder))

    await coordinator.consume(
        [.quotaReset(windowID: "secondary", remainingPercent: 44)],
        provider: notificationProvider(),
        settings: LinuxSettings())

    let sent = await recorder.values()
    #expect(sent.count == 1)
    #expect(sent[0].summary == "Quota restored")
    #expect(sent[0].body == "Claude / secondary / 44% remaining")
}

@Test func `transition threshold warnings honor task eight transitions and delivery preferences`() async {
    var settings = LinuxSettings()
    settings.quotaWarningSoundEnabled = false
    settings.quotaWarningOnScreenAlertEnabled = true
    let recorder = SentNotificationRecorder()
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(recorder: recorder))

    await coordinator.consume(
        [.quotaLow(windowID: "primary", threshold: 20, remainingPercent: 19)],
        provider: notificationProvider(),
        settings: settings)

    let sent = await recorder.values()
    #expect(sent.count == 1)
    #expect(sent[0].urgency == DesktopNotificationUrgency.critical.rawValue)
    #expect(!sent[0].sound)
}

@Test func `test notification sends one fixed non-account notification even when automatic notifications are disabled`() async {
    var settings = LinuxSettings()
    settings.sessionQuotaNotificationsEnabled = false
    settings.quotaWarningNotificationsEnabled = false
    settings.predictivePaceWarningsEnabled = false
    let recorder = SentNotificationRecorder()
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(recorder: recorder))

    await coordinator.testNotification(settings: settings)

    let sent = await recorder.values()
    #expect(sent.count == 1)
    #expect(sent[0].summary == "CodexBar notification test")
    #expect(sent[0].body == "CodexBar desktop notifications are working.")
    #expect(!sent[0].body.contains("@"))
}

@Test func `predictive pace warns once per provider account window and reset boundary`() async {
    let recorder = SentNotificationRecorder()
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(recorder: recorder))
    let resetAt = Date(timeIntervalSince1970: 10_000)
    let record = notificationRecord(resetAt: resetAt, account: "fixture@example.test")
    let pace = UsagePace.historical(
        expectedUsedPercent: 40,
        actualUsedPercent: 80,
        etaSeconds: 300,
        willLastToReset: false,
        runOutProbability: nil)

    await coordinator.consumePredictivePace(record: record, provider: notificationProvider(), settings: LinuxSettings(), pace: pace)
    await coordinator.consumePredictivePace(record: record, provider: notificationProvider(), settings: LinuxSettings(), pace: pace)

    let sent = await recorder.values()
    #expect(sent.count == 1)
    #expect(sent[0].body == "Claude / primary / projected exhaustion")
    #expect(!sent[0].body.contains("fixture@example.test"))
}

@Test func `predictive pace below full projection is silent and reset change rearms it`() async {
    let recorder = SentNotificationRecorder()
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(recorder: recorder))
    let settings = LinuxSettings()
    let projectedToLast = UsagePace.historical(
        expectedUsedPercent: 40,
        actualUsedPercent: 50,
        etaSeconds: nil,
        willLastToReset: true,
        runOutProbability: nil)
    let exhausted = UsagePace.historical(
        expectedUsedPercent: 40,
        actualUsedPercent: 80,
        etaSeconds: 300,
        willLastToReset: false,
        runOutProbability: nil)

    await coordinator.consumePredictivePace(
        record: notificationRecord(resetAt: Date(timeIntervalSince1970: 10_000), account: "fixture@example.test"),
        provider: notificationProvider(),
        settings: settings,
        pace: projectedToLast)
    await coordinator.consumePredictivePace(
        record: notificationRecord(resetAt: Date(timeIntervalSince1970: 10_000), account: "fixture@example.test"),
        provider: notificationProvider(),
        settings: settings,
        pace: exhausted)
    await coordinator.consumePredictivePace(
        record: notificationRecord(resetAt: Date(timeIntervalSince1970: 20_000), account: "fixture@example.test"),
        provider: notificationProvider(),
        settings: settings,
        pace: exhausted)

    #expect((await recorder.values()).count == 2)
}

@Test func `a drifting reset time does not re-arm the predictive warning`() async {
    let recorder = SentNotificationRecorder()
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(recorder: recorder))
    let pace = UsagePace.historical(
        expectedUsedPercent: 40,
        actualUsedPercent: 80,
        etaSeconds: 300,
        willLastToReset: false,
        runOutProbability: nil)

    // Measured from `~/.config/codexbar/history/opencodego.json`: a provider
    // reporting a relative TTL recomputes `resetsAt` as `now + ttl` on every
    // fetch, so 34 consecutive samples carried 34 distinct dates a fraction of
    // a second apart. One cycle, one warning.
    for drift in [0.0, 0.7, 0.4, 0.6, 0.5, 0.7, 0.4] {
        await coordinator.consumePredictivePace(
            record: notificationRecord(
                resetAt: Date(timeIntervalSince1970: 10_000 + drift),
                account: "fixture@example.test"),
            provider: notificationProvider(),
            settings: LinuxSettings(),
            pace: pace)
    }

    #expect((await recorder.values()).count == 1)
}

@Test func `a minute-rounded reset time does not re-arm the predictive warning`() async {
    let recorder = SentNotificationRecorder()
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(recorder: recorder))
    let pace = UsagePace.historical(
        expectedUsedPercent: 40,
        actualUsedPercent: 80,
        etaSeconds: 300,
        willLastToReset: false,
        runOutProbability: nil)

    // Claude's history oscillates its reset time by exactly ±60s as the
    // provider re-rounds the same cycle. Two dates, still one cycle.
    for offset in [0.0, 60.0, 0.0, 60.0, 0.0] {
        await coordinator.consumePredictivePace(
            record: notificationRecord(
                resetAt: Date(timeIntervalSince1970: 10_000 + offset),
                account: "fixture@example.test"),
            provider: notificationProvider(),
            settings: LinuxSettings(),
            pace: pace)
    }

    #expect((await recorder.values()).count == 1)
}

@Test func `predictive pace warnings are confined to the two forecastable providers`() async {
    let recorder = SentNotificationRecorder()
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(recorder: recorder))
    let pace = UsagePace.historical(
        expectedUsedPercent: 40,
        actualUsedPercent: 80,
        etaSeconds: 300,
        willLastToReset: false,
        runOutProbability: nil)

    // Upstream forecasts only Codex and Claude. OpenCode Go reports three
    // windows and a relative TTL, so it was the loudest of the providers that
    // should never have been in this path at all.
    for provider in [UsageProvider.opencodego, .zai, .kimi] {
        await coordinator.consumePredictivePace(
            record: notificationRecord(
                resetAt: Date(timeIntervalSince1970: 10_000),
                account: "fixture@example.test",
                providerID: provider.rawValue),
            provider: ProviderDescriptorRegistry.descriptor(for: provider),
            settings: LinuxSettings(),
            pace: pace)
    }

    #expect(await recorder.values().isEmpty)
}

@Test func `predictive pace warnings cover only the session and weekly lanes`() async {
    let recorder = SentNotificationRecorder()
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(recorder: recorder))
    let pace = UsagePace.historical(
        expectedUsedPercent: 40,
        actualUsedPercent: 80,
        etaSeconds: 300,
        willLastToReset: false,
        runOutProbability: nil)

    await coordinator.consumePredictivePace(
        record: notificationRecord(resetAt: Date(timeIntervalSince1970: 10_000), account: "fixture@example.test"),
        provider: notificationProvider(),
        settings: LinuxSettings(),
        windowID: "tertiary",
        pace: pace)

    #expect(await recorder.values().isEmpty)
}

@Test func `missing notification service never escapes the coordinator`() async {
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(
        recorder: SentNotificationRecorder(),
        result: .failure(.unavailable)))

    await coordinator.consume(
        [.quotaLow(windowID: "primary", threshold: 20, remainingPercent: 19)],
        provider: notificationProvider(),
        settings: LinuxSettings())
}

@Test func `usage store fans real refresh transitions into the notification coordinator`() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let configStore = CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
    try configStore.save(CodexBarConfig(providers: [ProviderConfig(id: .claude, enabled: true)]))
    let outcomes = NotificationOutcomeSequence([
        notificationOutcome(remainingPercent: 21),
        notificationOutcome(remainingPercent: 19),
    ])
    let sent = SentNotificationRecorder()
    let transitions = NotificationTransitionRecorder()
    let coordinator = LinuxNotificationCoordinator(sender: RecordingDesktopNotificationSender(recorder: sent))
    let store = LinuxUsageStore(
        configStore: configStore,
        fetch: { _, _, _, _ in await outcomes.next() },
        onUsageTransitions: { _, _ in Task { await transitions.append() } },
        notificationCoordinator: coordinator,
        notificationSettings: { LinuxSettings() },
        transitionEngine: UsageTransitionEngine(lowQuotaThresholds: [20]),
        onSnapshot: { _ in })

    store.refresh(providerID: "claude")
    await transitions.next()
    store.refresh(providerID: "claude")
    await transitions.next()

    #expect((await sent.next()).body == "Claude / primary / 19% remaining")
}

private func notificationProvider() -> ProviderDescriptor {
    ProviderDescriptorRegistry.descriptor(for: .claude)
}

private func notificationRecord(
    resetAt: Date,
    account: String,
    providerID: String = "claude") -> ProviderRefreshRecord
{
    let window = RateWindow(
        usedPercent: 80,
        windowMinutes: 300,
        resetsAt: resetAt,
        resetDescription: nil)
    // All three lanes are populated so a test asserting that a lane is skipped
    // cannot pass merely because the window was absent.
    let snapshot = UsageSnapshot(
        primary: window,
        secondary: window,
        tertiary: window,
        updatedAt: Date(timeIntervalSince1970: 1),
        identity: ProviderIdentitySnapshot(
            providerID: ProviderInstanceID(rawValue: providerID) ?? .claude,
            accountEmail: account,
            accountOrganization: nil,
            loginMethod: nil))
    let result = ProviderFetchResult(
        usage: snapshot,
        credits: nil,
        dashboard: nil,
        sourceLabel: "Fixture",
        strategyID: "fixture",
        strategyKind: .localProbe)
    return ProviderRefreshRecord(
        view: ProviderView(
            id: providerID,
            displayName: "Claude",
            iconResourceName: "claude",
            accentColorHex: "#000000",
            enabled: true),
        snapshot: snapshot,
        outcome: ProviderFetchOutcome(result: .success(result), attempts: []))
}

private func notificationOutcome(remainingPercent: Double) -> ProviderFetchOutcome {
    let snapshot = UsageSnapshot(
        primary: RateWindow(
            usedPercent: 100 - remainingPercent,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil),
        secondary: nil,
        updatedAt: Date(timeIntervalSince1970: 1))
    return ProviderFetchOutcome(result: .success(ProviderFetchResult(
        usage: snapshot,
        credits: nil,
        dashboard: nil,
        sourceLabel: "Fixture",
        strategyID: "fixture",
        strategyKind: .localProbe)), attempts: [])
}
