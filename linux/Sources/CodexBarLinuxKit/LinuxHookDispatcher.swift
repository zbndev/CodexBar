import CodexBarCore
import Foundation

public struct HookTestRuleSummary: Codable, Equatable, Sendable {
    public let ruleID: String
    public let success: Bool

    public init(ruleID: String, success: Bool) {
        self.ruleID = ruleID
        self.success = success
    }
}

/// Adapts Linux usage transitions to the shared Core hook runner.
public final class LinuxHookDispatcher: @unchecked Sendable {
    private let hooksConfig: @Sendable () -> HooksConfig
    private let rateLimiter: HookRateLimiter
    private let baseEnvironment: [String: String]

    public init(
        hooksConfig: @escaping @Sendable () -> HooksConfig,
        rateLimiter: HookRateLimiter = HookRateLimiter(),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment)
    {
        self.hooksConfig = hooksConfig
        self.rateLimiter = rateLimiter
        self.baseEnvironment = baseEnvironment
    }

    public func dispatch(transitions: [UsageTransition], provider: String) async {
        let config = self.hooksConfig()
        for transition in transitions {
            await HookRunner.dispatch(
                event: self.event(for: transition, provider: provider),
                config: config,
                rateLimiter: self.rateLimiter,
                baseEnvironment: self.baseEnvironment)
        }
    }

    public func event(for transition: UsageTransition, provider: String) -> HookEvent {
        Self.makeEvent(for: transition, provider: provider)
    }

    private static func makeEvent(for transition: UsageTransition, provider: String) -> HookEvent {
        let type: HookEventType
        let window: String?
        let usagePercent: Double?
        let status: String?
        switch transition {
        case let .quotaLow(windowID, _, remainingPercent):
            type = .quotaLow
            window = windowID
            usagePercent = 1 - (remainingPercent / 100)
            status = nil
        case let .quotaReached(windowID):
            type = .quotaReached
            window = windowID
            usagePercent = 1
            status = nil
        case let .quotaReset(windowID):
            type = .quotaReset
            window = windowID
            usagePercent = 0
            status = nil
        case .refreshFailed:
            type = .refreshFailed
            window = nil
            usagePercent = nil
            status = "error"
        case .providerUnavailable:
            type = .providerUnavailable
            window = nil
            usagePercent = nil
            status = "unavailable"
        case .providerRecovered:
            type = .providerRecovered
            window = nil
            usagePercent = nil
            status = "available"
        }
        return HookEvent(
            event: type,
            provider: provider,
            window: window,
            usagePercent: usagePercent,
            status: status,
            timestamp: Date())
    }

    public func testHook(event: HookEventType, provider: String) async -> [HookTestRuleSummary] {
        let event = Self.representativeEvent(type: event, provider: provider)
        let rules = self.hooksConfig().matchingRules(for: event)
        var summaries: [HookTestRuleSummary] = []
        for rule in rules {
            do {
                _ = try await HookRunner.run(rule: rule, event: event, baseEnvironment: self.baseEnvironment)
                summaries.append(HookTestRuleSummary(ruleID: rule.id, success: true))
            } catch {
                summaries.append(HookTestRuleSummary(ruleID: rule.id, success: false))
            }
        }
        return summaries
    }

    private static func representativeEvent(type: HookEventType, provider: String) -> HookEvent {
        let transition: UsageTransition
        switch type {
        case .quotaLow:
            transition = .quotaLow(windowID: "primary", threshold: 20, remainingPercent: 1)
        case .quotaReached:
            transition = .quotaReached(windowID: "primary")
        case .quotaReset:
            transition = .quotaReset(windowID: "primary")
        case .refreshFailed:
            transition = .refreshFailed
        case .providerUnavailable:
            transition = .providerUnavailable
        case .providerRecovered:
            transition = .providerRecovered
        }
        return Self.makeEvent(for: transition, provider: provider)
    }
}
