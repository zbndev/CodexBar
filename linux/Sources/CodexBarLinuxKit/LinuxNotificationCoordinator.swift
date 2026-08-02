import CodexBarCore
import Crypto
import Foundation

public final class LinuxNotificationCoordinator: @unchecked Sendable {
    private struct PredictiveWarningKey: Hashable {
        let providerID: String
        let accountDiscriminator: String
        let windowID: String
        let resetAt: Date
    }

    private let sender: any DesktopNotificationSending
    private let lock = NSLock()
    private var predictiveWarnings = Set<PredictiveWarningKey>()

    public init(sender: any DesktopNotificationSending = DesktopNotificationClient()) {
        self.sender = sender
    }

    public func consume(
        _ transitions: [UsageTransition],
        provider: ProviderDescriptor,
        settings: LinuxSettings) async
    {
        for transition in transitions {
            switch transition {
            case let .quotaLow(windowID, _, remainingPercent):
                guard settings.quotaWarningNotificationsEnabled,
                      self.warningLaneEnabled(windowID: windowID, settings: settings)
                else { continue }
                await self.send(
                    summary: "Quota warning",
                    body: self.quotaBody(
                        provider: provider,
                        windowID: windowID,
                        remainingPercent: remainingPercent),
                    settings: settings)
            case let .quotaReached(windowID):
                guard settings.sessionQuotaNotificationsEnabled else { continue }
                await self.send(
                    summary: "Quota depleted",
                    body: self.quotaBody(provider: provider, windowID: windowID, remainingPercent: 0),
                    settings: settings)
            case let .quotaReset(windowID):
                guard settings.sessionQuotaNotificationsEnabled else { continue }
                await self.send(
                    summary: "Quota restored",
                    body: self.quotaBody(provider: provider, windowID: windowID, remainingPercent: 100),
                    settings: settings)
            case .refreshFailed, .providerUnavailable, .providerRecovered:
                continue
            }
        }
    }

    public func consume(
        record: ProviderRefreshRecord,
        transitions: [UsageTransition],
        provider: ProviderDescriptor,
        settings: LinuxSettings) async
    {
        await self.consume(transitions, provider: provider, settings: settings)
        guard settings.predictivePaceWarningsEnabled,
              let snapshot = record.snapshot
        else { return }
        for (windowID, window) in Self.windows(in: snapshot) {
            guard let pace = UsagePace.weekly(window: window, now: snapshot.updatedAt) else { continue }
            await self.consumePredictivePace(
                record: record,
                provider: provider,
                settings: settings,
                windowID: windowID,
                pace: pace)
        }
    }

    public func consumePredictivePace(
        record: ProviderRefreshRecord,
        provider: ProviderDescriptor,
        settings: LinuxSettings,
        pace: UsagePace) async
    {
        await self.consumePredictivePace(
            record: record,
            provider: provider,
            settings: settings,
            windowID: "primary",
            pace: pace)
    }

    public func testNotification(settings: LinuxSettings) async {
        await self.send(
            summary: "CodexBar notification test",
            body: "CodexBar desktop notifications are working.",
            settings: settings)
    }

    private func consumePredictivePace(
        record: ProviderRefreshRecord,
        provider: ProviderDescriptor,
        settings: LinuxSettings,
        windowID: String,
        pace: UsagePace) async
    {
        guard settings.predictivePaceWarningsEnabled,
              !pace.willLastToReset,
              let etaSeconds = pace.etaSeconds,
              etaSeconds > 0,
              let snapshot = record.snapshot,
              let resetAt = Self.window(id: windowID, in: snapshot)?.resetsAt,
              etaSeconds < resetAt.timeIntervalSince(snapshot.updatedAt)
        else { return }

        let key = PredictiveWarningKey(
            providerID: record.view.id,
            accountDiscriminator: Self.accountDiscriminator(snapshot: snapshot, providerID: record.view.id),
            windowID: windowID,
            resetAt: resetAt)
        let shouldSend = self.lock.withLock { self.predictiveWarnings.insert(key).inserted }
        guard shouldSend else { return }
        await self.send(
            summary: "Projected quota exhaustion",
            body: "\(provider.metadata.displayName) / \(windowID) / projected exhaustion",
            settings: settings)
    }

    private func send(summary: String, body: String, settings: LinuxSettings) async {
        let urgency = settings.quotaWarningOnScreenAlertEnabled
            ? DesktopNotificationUrgency.critical.rawValue
            : DesktopNotificationUrgency.normal.rawValue
        do {
            try await self.sender.send(
                summary: summary,
                body: body,
                urgency: urgency,
                sound: settings.quotaWarningSoundEnabled)
        } catch {
        }
    }

    private func warningLaneEnabled(windowID: String, settings: LinuxSettings) -> Bool {
        switch windowID {
        case "primary": settings.quotaWarningSessionEnabled
        case "secondary": settings.quotaWarningWeeklyEnabled
        default: true
        }
    }

    private func quotaBody(
        provider: ProviderDescriptor,
        windowID: String,
        remainingPercent: Double) -> String
    {
        "\(provider.metadata.displayName) / \(windowID) / \(Int(remainingPercent.rounded()))% remaining"
    }

    private static func accountDiscriminator(snapshot: UsageSnapshot, providerID: String) -> String {
        let identity = snapshot.identity?.accountEmail
            ?? snapshot.identity?.accountOrganization
            ?? "anonymous"
        return SHA256.hash(data: Data("\(providerID)\u{0}\(identity)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func windows(in snapshot: UsageSnapshot) -> [(String, RateWindow)] {
        [("primary", snapshot.primary), ("secondary", snapshot.secondary), ("tertiary", snapshot.tertiary)]
            .compactMap { id, window in window.map { (id, $0) } }
            + (snapshot.extraRateWindows ?? []).map { ($0.id, $0.window) }
    }

    private static func window(id: String, in snapshot: UsageSnapshot) -> RateWindow? {
        self.windows(in: snapshot).first { $0.0 == id }?.1
    }
}
