import CodexBarCore
import Crypto
import Foundation

public final class LinuxNotificationCoordinator: @unchecked Sendable {
    private struct PredictiveWarningKey: Hashable {
        let providerID: String
        let accountDiscriminator: String
        let windowID: String
        let windowMinutes: Int?
        let resetAt: Date

        /// One provider account's one window — the lane a warning is scoped to,
        /// independent of which reset cycle it was observed in.
        func sharesLane(with other: Self) -> Bool {
            self.providerID == other.providerID
                && self.accountDiscriminator == other.accountDiscriminator
                && self.windowID == other.windowID
        }

        /// Whether two observations describe the same reset cycle.
        ///
        /// Keying on the exact `resetAt` meant every refresh looked like a new
        /// cycle for any provider that reports a *relative* TTL: `resetsAt` is
        /// recomputed as `now + ttl` per fetch, so it lands a fraction of a
        /// second away each time. Measured in
        /// `~/.config/codexbar/history/opencodego.json`: 34 consecutive samples,
        /// 34 distinct dates. Claude instead re-rounds the same cycle and
        /// oscillates by exactly ±60s. Both re-armed the warning on every
        /// refresh, so the notification repeated at the refresh interval.
        ///
        /// The tolerance is upstream's, from
        /// `PredictivePaceWarningResetWindow.belongsToSameCycle`: half the
        /// window, floored at five minutes.
        func belongsToSameCycle(as other: Self) -> Bool {
            guard self.windowMinutes == other.windowMinutes else { return false }
            let tolerance = self.windowMinutes.map { max(TimeInterval($0 * 60) / 2, 300) } ?? 300
            return abs(self.resetAt.timeIntervalSince(other.resetAt)) < tolerance
        }
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
              let window = Self.window(id: windowID, in: snapshot),
              let resetAt = window.resetsAt,
              etaSeconds < resetAt.timeIntervalSince(snapshot.updatedAt)
        else { return }

        let key = PredictiveWarningKey(
            providerID: record.view.id,
            accountDiscriminator: Self.accountDiscriminator(snapshot: snapshot, providerID: record.view.id),
            windowID: windowID,
            windowMinutes: window.windowMinutes,
            resetAt: resetAt)
        // Replacing the lane's keys rather than accumulating them lets a drifting
        // reset time follow the provider without re-alerting, and keeps the set
        // from growing by one entry per refresh.
        let shouldSend = self.lock.withLock { () -> Bool in
            let lane = self.predictiveWarnings.filter { $0.sharesLane(with: key) }
            let warnedThisCycle = lane.contains { $0.belongsToSameCycle(as: key) }
            self.predictiveWarnings.subtract(lane)
            self.predictiveWarnings.insert(key)
            return !warnedThisCycle
        }
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
