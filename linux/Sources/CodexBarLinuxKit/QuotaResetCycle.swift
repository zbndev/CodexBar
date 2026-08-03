import Foundation

/// Whether two observed reset boundaries describe the same quota cycle.
///
/// No provider reports a stable boundary. Claude re-rounds the same cycle and
/// oscillates by exactly ±60s; providers reporting a *relative* TTL recompute
/// `resetsAt` as `now + ttl` per fetch and land a fraction of a second away
/// every time. Measured in `~/.config/codexbar/history/opencodego.json`: 34
/// consecutive samples, 34 distinct dates. Comparing boundaries for equality
/// therefore reads a new cycle out of nearly every refresh.
///
/// The tolerance is upstream's, from
/// `PredictivePaceWarningResetWindow.belongsToSameCycle`: half the window,
/// floored at five minutes.
enum QuotaResetCycle {
    static func belongsToSameCycle(_ lhs: Date, _ rhs: Date, windowMinutes: Int?) -> Bool {
        let tolerance = windowMinutes.map { max(TimeInterval($0 * 60) / 2, 300) } ?? 300
        return abs(lhs.timeIntervalSince(rhs)) < tolerance
    }
}
