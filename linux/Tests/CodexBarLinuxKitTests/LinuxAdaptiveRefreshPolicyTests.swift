import Foundation
import Testing

@testable import CodexBarLinuxKit

struct LinuxAdaptiveRefreshPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test
    func `adaptive refresh uses two minutes through the five minute menu boundary`() {
        let decision = self.adaptive(lastMenuOpenAt: self.now.addingTimeInterval(-5 * 60))

        #expect(decision == .init(delay: .seconds(2 * 60), reason: .recentInteraction))
    }

    @Test
    func `adaptive refresh uses five minutes through the one hour menu boundary`() {
        let decision = self.adaptive(lastMenuOpenAt: self.now.addingTimeInterval(-60 * 60))

        #expect(decision == .init(delay: .seconds(5 * 60), reason: .warm))
    }

    @Test
    func `adaptive refresh uses fifteen minutes before the four hour menu boundary`() {
        let decision = self.adaptive(lastMenuOpenAt: self.now.addingTimeInterval(-(4 * 60 * 60 - 1)))

        #expect(decision == .init(delay: .seconds(15 * 60), reason: .idle))
    }

    @Test
    func `adaptive refresh uses thirty minutes at the four hour menu boundary`() {
        let decision = self.adaptive(lastMenuOpenAt: self.now.addingTimeInterval(-4 * 60 * 60))

        #expect(decision == .init(delay: .seconds(30 * 60), reason: .longIdle))
    }

    @Test
    func `adaptive refresh treats a future menu timestamp as recent`() {
        let decision = self.adaptive(lastMenuOpenAt: self.now.addingTimeInterval(60))

        #expect(decision == .init(delay: .seconds(2 * 60), reason: .recentInteraction))
    }

    @Test
    func `adaptive refresh uses thirty minutes without a menu timestamp`() {
        let decision = self.adaptive(lastMenuOpenAt: nil)

        #expect(decision == .init(delay: .seconds(30 * 60), reason: .longIdle))
    }

    @Test
    func `agent aware refresh caps an idle decision at five minutes`() {
        let decision = LinuxAdaptiveRefreshPolicy.nextDecision(for: .init(
            interval: .adaptiveAgentAware,
            now: self.now,
            lastMenuOpenAt: nil,
            lastCodingActivityAt: self.now.addingTimeInterval(-5 * 60),
            powerState: .nominal))

        #expect(decision == .init(delay: .seconds(5 * 60), reason: .codingActivity))
    }

    @Test
    func `constrained power overrides menu and agent activity`() {
        let decision = LinuxAdaptiveRefreshPolicy.nextDecision(for: .init(
            interval: .adaptiveAgentAware,
            now: self.now,
            lastMenuOpenAt: self.now,
            lastCodingActivityAt: self.now,
            powerState: .constrained))

        #expect(decision == .init(delay: .seconds(30 * 60), reason: .constrained))
    }

    @Test
    func `fixed and manual refresh intervals remain unchanged`() {
        let fixed = LinuxAdaptiveRefreshPolicy.nextDecision(for: .init(
            interval: .fifteenMinutes,
            now: self.now,
            lastMenuOpenAt: self.now,
            lastCodingActivityAt: self.now,
            powerState: .constrained))
        let manual = LinuxAdaptiveRefreshPolicy.nextDecision(for: .init(
            interval: .manual,
            now: self.now,
            lastMenuOpenAt: self.now,
            lastCodingActivityAt: self.now,
            powerState: .nominal))

        #expect(fixed == .init(delay: .seconds(15 * 60), reason: .fixed))
        #expect(manual == nil)
    }

    @Test
    func `power reader constrains low battery and hot thermal fixtures`() throws {
        let root = try self.makeSysfsFixture()
        try self.write("Discharging", to: root.appending(path: "class/power_supply/BAT0/status"))
        try self.write("20", to: root.appending(path: "class/power_supply/BAT0/capacity"))
        #expect(LinuxPowerState.current(sysfsRoot: root) == .constrained)

        try self.write("Charging", to: root.appending(path: "class/power_supply/BAT0/status"))
        try self.write("85000", to: root.appending(path: "class/thermal/thermal_zone0/temp"))
        #expect(LinuxPowerState.current(sysfsRoot: root) == .constrained)
    }

    @Test
    func `power reader treats missing sysfs as nominal`() {
        let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

        #expect(LinuxPowerState.current(sysfsRoot: missing) == .nominal)
    }

    @Test
    func `scheduler advances adaptive refresh without overlapping sleep tasks`() async {
        let sleeper = RefreshSleepRecorder()
        let scheduler = LinuxRefreshScheduler(
            clock: { self.now },
            powerState: { .nominal },
            lastCodingActivityAt: { nil },
            refresh: {},
            sleep: sleeper.sleep,
            diagnostic: { _ in })

        scheduler.apply(.adaptive)
        #expect(await sleeper.nextDelay() == .seconds(30 * 60))
        scheduler.menuOpened()
        #expect(await sleeper.nextDelay() == .seconds(2 * 60))
        #expect(await sleeper.maximumConcurrentSleeps == 1)

        scheduler.apply(.manual)
        scheduler.stop()
    }

    private func adaptive(lastMenuOpenAt: Date?) -> LinuxAdaptiveRefreshPolicy.Decision {
        LinuxAdaptiveRefreshPolicy.nextDecision(for: .init(
            interval: .adaptive,
            now: self.now,
            lastMenuOpenAt: lastMenuOpenAt,
            lastCodingActivityAt: nil,
            powerState: .nominal))!
    }

    private func makeSysfsFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root.appending(path: "class/power_supply/BAT0"),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appending(path: "class/thermal/thermal_zone0"),
            withIntermediateDirectories: true)
        return root
    }

    private func write(_ value: String, to url: URL) throws {
        try value.write(to: url, atomically: true, encoding: .utf8)
    }
}

actor RefreshSleepRecorder {
    private var delays: [Duration] = []
    private var delayWaiters: [CheckedContinuation<Duration, Never>] = []
    private var blockers: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private(set) var maximumConcurrentSleeps = 0

    func sleep(for delay: Duration) async -> Bool {
        if let waiter = self.delayWaiters.popLast() {
            waiter.resume(returning: delay)
        } else {
            self.delays.append(delay)
        }
        let id = UUID()
        self.maximumConcurrentSleeps = max(self.maximumConcurrentSleeps, self.blockers.count + 1)
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                self.blockers[id] = continuation
            }
        }, onCancel: {
            Task { await self.cancel(id) }
        })
    }

    func nextDelay() async -> Duration {
        if !self.delays.isEmpty { return self.delays.removeFirst() }
        return await withCheckedContinuation { self.delayWaiters.append($0) }
    }

    func resumeNext() {
        guard let id = self.blockers.keys.first else { return }
        self.blockers.removeValue(forKey: id)?.resume(returning: true)
    }

    private func cancel(_ id: UUID) {
        self.blockers.removeValue(forKey: id)?.resume(returning: false)
    }
}
