import Foundation

public enum LinuxAdaptiveRefreshPolicy {
    public enum Reason: String, Equatable, Sendable {
        case recentInteraction
        case codingActivity
        case warm
        case idle
        case longIdle
        case constrained
        case fixed
    }

    public struct Decision: Equatable, Sendable {
        public let delay: Duration
        public let reason: Reason

        public init(delay: Duration, reason: Reason) {
            self.delay = delay
            self.reason = reason
        }
    }

    public struct Input: Sendable {
        public let interval: RefreshInterval
        public let now: Date
        public let lastMenuOpenAt: Date?
        public let lastCodingActivityAt: Date?
        public let powerState: LinuxPowerState

        public init(
            interval: RefreshInterval,
            now: Date,
            lastMenuOpenAt: Date?,
            lastCodingActivityAt: Date?,
            powerState: LinuxPowerState)
        {
            self.interval = interval
            self.now = now
            self.lastMenuOpenAt = lastMenuOpenAt
            self.lastCodingActivityAt = lastCodingActivityAt
            self.powerState = powerState
        }
    }

    private static let recentInteractionThreshold: TimeInterval = 5 * 60
    private static let warmThreshold: TimeInterval = 60 * 60
    private static let idleThreshold: TimeInterval = 4 * 60 * 60
    private static let codingActivityThreshold: TimeInterval = 5 * 60

    private static let recentInteractionDelay: Duration = .seconds(2 * 60)
    private static let warmDelay: Duration = .seconds(5 * 60)
    private static let idleDelay: Duration = .seconds(15 * 60)
    private static let longIdleDelay: Duration = .seconds(30 * 60)
    private static let constrainedDelay: Duration = .seconds(30 * 60)
    private static let codingActivityDelayCap: Duration = .seconds(5 * 60)

    public static func nextDecision(for input: Input) -> Decision? {
        switch input.interval {
        case .manual:
            return nil
        case .oneMinute, .twoMinutes, .fiveMinutes, .fifteenMinutes, .thirtyMinutes:
            guard let seconds = input.interval.seconds else { return nil }
            return Decision(delay: .seconds(Int64(seconds)), reason: .fixed)
        case .adaptive, .adaptiveAgentAware:
            return self.adaptiveDecision(for: input)
        }
    }

    private static func adaptiveDecision(for input: Input) -> Decision {
        guard input.powerState == .nominal else {
            return Decision(delay: Self.constrainedDelay, reason: .constrained)
        }
        let menuDecision = self.menuDecision(for: input)
        guard input.interval == .adaptiveAgentAware,
              let lastCodingActivityAt = input.lastCodingActivityAt,
              input.now.timeIntervalSince(lastCodingActivityAt) <= Self.codingActivityThreshold,
              menuDecision.delay > Self.codingActivityDelayCap
        else { return menuDecision }
        return Decision(delay: Self.codingActivityDelayCap, reason: .codingActivity)
    }

    private static func menuDecision(for input: Input) -> Decision {
        guard let lastMenuOpenAt = input.lastMenuOpenAt else {
            return Decision(delay: Self.longIdleDelay, reason: .longIdle)
        }
        let age = input.now.timeIntervalSince(lastMenuOpenAt)
        if age <= Self.recentInteractionThreshold {
            return Decision(delay: Self.recentInteractionDelay, reason: .recentInteraction)
        }
        if age <= Self.warmThreshold {
            return Decision(delay: Self.warmDelay, reason: .warm)
        }
        if age < Self.idleThreshold {
            return Decision(delay: Self.idleDelay, reason: .idle)
        }
        return Decision(delay: Self.longIdleDelay, reason: .longIdle)
    }
}

final class LinuxRefreshScheduler: @unchecked Sendable {
    typealias Sleeper = @Sendable (Duration) async -> Bool

    private struct ScheduledRefresh {
        let token: UUID
        let deadline: Date
        let task: Task<Void, Never>
    }

    private let lock = NSLock()
    private let clock: @Sendable () -> Date
    private let powerState: @Sendable () -> LinuxPowerState
    private let lastCodingActivityAt: @Sendable () -> Date?
    private let refresh: @Sendable () -> Void
    private let sleep: Sleeper
    private let diagnostic: @Sendable (LinuxAdaptiveRefreshPolicy.Decision) -> Void
    private var interval: RefreshInterval = .manual
    private var fixedDelay: Duration?
    private var lastMenuOpenAt: Date?
    private var scheduled: ScheduledRefresh?

    init(
        clock: @escaping @Sendable () -> Date,
        powerState: @escaping @Sendable () -> LinuxPowerState,
        lastCodingActivityAt: @escaping @Sendable () -> Date?,
        refresh: @escaping @Sendable () -> Void,
        sleep: @escaping Sleeper,
        diagnostic: @escaping @Sendable (LinuxAdaptiveRefreshPolicy.Decision) -> Void)
    {
        self.clock = clock
        self.powerState = powerState
        self.lastCodingActivityAt = lastCodingActivityAt
        self.refresh = refresh
        self.sleep = sleep
        self.diagnostic = diagnostic
    }

    func apply(_ interval: RefreshInterval) {
        self.lock.withLock {
            self.interval = interval
            self.fixedDelay = nil
        }
        self.replaceSchedule(onlyIfEarlier: false)
    }

    func startFixed(intervalSeconds: Double) {
        self.lock.withLock {
            self.interval = .oneMinute
            self.fixedDelay = .seconds(Int64(intervalSeconds))
        }
        self.replaceSchedule(onlyIfEarlier: false)
    }

    func menuOpened() {
        self.lock.withLock { self.lastMenuOpenAt = self.clock() }
        self.advanceSchedule()
    }

    func agentActivityChanged() {
        self.advanceSchedule()
    }

    func refreshCompleted() {
        self.replaceSchedule(onlyIfEarlier: false)
    }

    func stop() {
        let previous = self.lock.withLock { () -> ScheduledRefresh? in
            self.interval = .manual
            self.fixedDelay = nil
            defer { self.scheduled = nil }
            return self.scheduled
        }
        previous?.task.cancel()
    }

    private func advanceSchedule() {
        let isAdaptive = self.lock.withLock {
            self.interval == .adaptive || self.interval == .adaptiveAgentAware
        }
        guard isAdaptive else { return }
        self.replaceSchedule(onlyIfEarlier: true)
    }

    private func replaceSchedule(onlyIfEarlier: Bool) {
        let schedulingInput = self.lock.withLock { () -> (LinuxAdaptiveRefreshPolicy.Input, Duration?) in
            let input = LinuxAdaptiveRefreshPolicy.Input(
                interval: self.interval,
                now: self.clock(),
                lastMenuOpenAt: self.lastMenuOpenAt,
                lastCodingActivityAt: self.lastCodingActivityAt(),
                powerState: self.powerState())
            return (input, self.fixedDelay)
        }
        let input = schedulingInput.0
        let decision = schedulingInput.1.map {
            LinuxAdaptiveRefreshPolicy.Decision(delay: $0, reason: .fixed)
        } ?? LinuxAdaptiveRefreshPolicy.nextDecision(for: input)
        guard let decision else {
            let previous = self.lock.withLock { () -> ScheduledRefresh? in
                defer { self.scheduled = nil }
                return self.scheduled
            }
            previous?.task.cancel()
            return
        }
        let deadline = input.now.addingTimeInterval(Self.seconds(in: decision.delay))
        let replacement = self.lock.withLock { () -> ScheduledRefresh? in
            if onlyIfEarlier,
               let scheduled = self.scheduled,
               scheduled.deadline <= deadline
            {
                return nil
            }
            let previous = self.scheduled
            let token = UUID()
            let task = Task.detached { [weak self, previousTask = previous?.task] in
                if let previousTask { await previousTask.value }
                guard let self, !Task.isCancelled, self.isCurrent(token) else { return }
                self.diagnostic(decision)
                guard await self.sleep(decision.delay), !Task.isCancelled, self.isCurrent(token) else {
                    self.clear(token)
                    return
                }
                self.clear(token)
                self.refresh()
            }
            self.scheduled = ScheduledRefresh(token: token, deadline: deadline, task: task)
            return previous
        }
        replacement?.task.cancel()
    }

    private func isCurrent(_ token: UUID) -> Bool {
        self.lock.withLock { self.scheduled?.token == token }
    }

    private func clear(_ token: UUID) {
        self.lock.withLock {
            guard self.scheduled?.token == token else { return }
            self.scheduled = nil
        }
    }

    static func sleep(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }

    private static func seconds(in duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
