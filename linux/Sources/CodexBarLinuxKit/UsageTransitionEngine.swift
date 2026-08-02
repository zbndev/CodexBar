import CodexBarCore
import Crypto
import Foundation

public enum UsageTransition: Equatable, Sendable {
    case quotaLow(windowID: String, threshold: Int, remainingPercent: Double)
    case quotaReached(windowID: String)
    case quotaReset(windowID: String)
    case refreshFailed
    case providerUnavailable
    case providerRecovered
}

/// Reduces provider refresh records into deduplicated usage transitions.
/// Callers serialize `transitions(for:)` with their own usage-store lock.
public final class UsageTransitionEngine: @unchecked Sendable {
    private struct WindowKey: Hashable {
        let providerID: String
        let accountDiscriminator: String
        let windowID: String
    }

    private struct WindowState {
        let remainingPercent: Double
        let resetBoundary: Date?
        let hasReachedQuota: Bool
    }

    private let lowQuotaThresholds: [Int]
    private var windows: [WindowKey: WindowState] = [:]
    private var unavailableProviders: Set<String> = []

    public init(lowQuotaThresholds: [Int] = [20]) {
        self.lowQuotaThresholds = Array(Set(lowQuotaThresholds.filter { 0 ... 100 ~= $0 })).sorted(by: >)
    }

    public func transitions(for record: ProviderRefreshRecord) -> [UsageTransition] {
        guard let snapshot = record.snapshot else {
            return self.failedTransitions(for: record)
        }

        var transitions: [UsageTransition] = []
        if self.unavailableProviders.remove(record.view.id) != nil {
            transitions.append(.providerRecovered)
        }

        let accountDiscriminator = Self.accountDiscriminator(
            stableIdentity: snapshot.identity?.accountEmail
                ?? snapshot.identity?.accountOrganization
                ?? "anonymous",
            providerID: record.view.id)
        let currentWindows = Self.windows(in: snapshot)
        let currentKeys = Set(currentWindows.map {
            WindowKey(
                providerID: record.view.id,
                accountDiscriminator: accountDiscriminator,
                windowID: $0.id)
        })
        self.windows = self.windows.filter { key, _ in
            key.providerID != record.view.id || currentKeys.contains(key)
        }

        for window in currentWindows {
            let key = WindowKey(
                providerID: record.view.id,
                accountDiscriminator: accountDiscriminator,
                windowID: window.id)
            let remainingPercent = window.value.remainingPercent
            let prior = self.windows[key]
            let reset = prior.map {
                $0.resetBoundary != window.value.resetsAt && remainingPercent > $0.remainingPercent
            } ?? false

            if reset {
                transitions.append(.quotaReset(windowID: window.id))
            } else if let prior {
                for threshold in self.lowQuotaThresholds where
                    prior.remainingPercent > Double(threshold) && remainingPercent <= Double(threshold)
                {
                    transitions.append(.quotaLow(
                        windowID: window.id,
                        threshold: threshold,
                        remainingPercent: remainingPercent))
                }
            }

            let hasReachedQuota = remainingPercent == 0
            if hasReachedQuota, prior?.hasReachedQuota != true {
                transitions.append(.quotaReached(windowID: window.id))
            }
            self.windows[key] = WindowState(
                remainingPercent: remainingPercent,
                resetBoundary: window.value.resetsAt,
                hasReachedQuota: hasReachedQuota)
        }
        return transitions
    }

    public func retainState(forProviderIDs providerIDs: Set<String>) {
        self.windows = self.windows.filter { providerIDs.contains($0.key.providerID) }
        self.unavailableProviders = self.unavailableProviders.filter(providerIDs.contains)
    }

    private func failedTransitions(for record: ProviderRefreshRecord) -> [UsageTransition] {
        var transitions: [UsageTransition] = [.refreshFailed]
        let providerIsUnavailable = !record.outcome.attempts.isEmpty
            && record.outcome.attempts.allSatisfy { !$0.wasAvailable }
        if providerIsUnavailable, self.unavailableProviders.insert(record.view.id).inserted {
            transitions.append(.providerUnavailable)
        }
        return transitions
    }

    private static func accountDiscriminator(stableIdentity: String, providerID: String) -> String {
        let material = Data("\(providerID)\u{0}\(stableIdentity)".utf8)
        return SHA256.hash(data: material).map { String(format: "%02x", $0) }.joined()
    }

    private static func windows(in snapshot: UsageSnapshot) -> [(id: String, value: RateWindow)] {
        let base: [(String, RateWindow?)] = [
            ("primary", snapshot.primary),
            ("secondary", snapshot.secondary),
            ("tertiary", snapshot.tertiary),
        ]
        return base.compactMap { id, window in window.map { (id, $0) } }
            + (snapshot.extraRateWindows ?? []).map { ($0.id, $0.window) }
    }
}
