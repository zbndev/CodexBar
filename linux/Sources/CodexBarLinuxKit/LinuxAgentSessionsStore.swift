import CodexBarCore
import Foundation

/// Scans local coding-agent metadata and publishes display-only session rows.
public final class LinuxAgentSessionsStore: @unchecked Sendable {
    public typealias Scanner = @Sendable (Date, [String: String], Bool) async -> [AgentSession]

    private struct InFlightScan {
        let id: UUID
        let task: Task<[AgentSession], Never>
    }

    private let lock = NSLock()
    private let scan: Scanner
    private let onChange: @Sendable () -> Void
    private let onRefreshJoin: @Sendable () async -> Void
    private var payload = AgentSessionsPayload(scannedAt: .distantPast, sessions: [], errorMessage: nil)
    private var lastActivity: Date?
    private var includeFileOnlySessions = true
    private var popupOpen = false
    private var inFlight: InFlightScan?
    private var timerTask: Task<Void, Never>?

    public init(
        scan: @escaping Scanner,
        onChange: @escaping @Sendable () -> Void = {},
        onRefreshJoin: @escaping @Sendable () async -> Void = {})
    {
        self.scan = scan
        self.onChange = onChange
        self.onRefreshJoin = onRefreshJoin
    }

    public convenience init(onChange: @escaping @Sendable () -> Void = {}) {
        self.init(scan: { now, environment, includeFileOnlySessions in
            await LocalAgentSessionScanner().scan(
                now: now,
                environment: environment,
                includeFileOnlySessions: includeFileOnlySessions)
        }, onChange: onChange)
    }

    public func start() {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runTimer()
        }
        let accepted = self.lock.withLock { () -> Bool in
            guard self.timerTask == nil else { return false }
            self.timerTask = task
            return true
        }
        if !accepted { task.cancel() }
    }

    public func stop() async {
        let work = self.lock.withLock { () -> (Task<Void, Never>?, InFlightScan?) in
            let timer = self.timerTask
            let scan = self.inFlight
            self.timerTask = nil
            timer?.cancel()
            scan?.task.cancel()
            return (timer, scan)
        }
        _ = await work.0?.value
        _ = await work.1?.task.value
        self.lock.withLock {
            if self.inFlight?.id == work.1?.id {
                self.inFlight = nil
            }
        }
    }

    public func setPopupOpen(_ open: Bool) {
        let previousTimer = self.lock.withLock { () -> Task<Void, Never>? in
            guard self.popupOpen != open else { return nil }
            self.popupOpen = open
            let previous = self.timerTask
            self.timerTask = nil
            previous?.cancel()
            return previous
        }
        guard previousTimer != nil else { return }
        self.start()
    }

    public func setIncludeFileOnlySessions(_ enabled: Bool) {
        self.lock.withLock { self.includeFileOnlySessions = enabled }
    }

    public func currentPayload() -> AgentSessionsPayload {
        self.lock.withLock { self.payload }
    }

    public var lastCodingActivityAt: Date? {
        self.lock.withLock { self.lastActivity }
    }

    @discardableResult
    public func refresh(
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment) async -> AgentSessionsPayload
    {
        let work = self.lock.withLock { () -> (InFlightScan, Bool) in
            if let inFlight { return (inFlight, true) }
            let id = UUID()
            let includeFileOnlySessions = self.includeFileOnlySessions
            let task = Task { [scan] in
                await scan(now, environment, includeFileOnlySessions)
            }
            let inFlight = InFlightScan(id: id, task: task)
            self.inFlight = inFlight
            return (inFlight, false)
        }
        if work.1 { await self.onRefreshJoin() }
        let sessions = await work.0.task.value
        let updated = Self.payload(from: sessions, scannedAt: now)
        let published = self.lock.withLock { () -> Bool in
            guard self.inFlight?.id == work.0.id else { return false }
            self.inFlight = nil
            self.payload = updated
            self.lastActivity = updated.sessions.map(\.lastActivityAt).max()
            return true
        }
        if published { self.onChange() }
        return self.currentPayload()
    }

    private func runTimer() async {
        await self.refresh()
        while !Task.isCancelled {
            let seconds = self.lock.withLock { self.popupOpen ? 15.0 : 60.0 }
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self.refresh()
        }
    }

    private static func payload(from sessions: [AgentSession], scannedAt: Date) -> AgentSessionsPayload {
        var unique: [String: AgentSession] = [:]
        for session in sessions {
            guard let existing = unique[session.id] else {
                unique[session.id] = session
                continue
            }
            if Self.precedes(session, existing, scannedAt: scannedAt) {
                unique[session.id] = session
            }
        }
        let views = unique.values.sorted {
            Self.precedes($0, $1, scannedAt: scannedAt)
        }.map {
            AgentSessionView(
                id: $0.id,
                provider: $0.provider.rawValue,
                state: $0.state.rawValue,
                projectName: Self.sanitizedLabel($0.projectName),
                sessionName: Self.sanitizedLabel($0.sessionName),
                lastActivityAt: Self.activity(for: $0, fallback: scannedAt))
        }
        return AgentSessionsPayload(scannedAt: scannedAt, sessions: views, errorMessage: nil)
    }

    private static func precedes(_ lhs: AgentSession, _ rhs: AgentSession, scannedAt: Date) -> Bool {
        if lhs.state != rhs.state { return lhs.state == .active }
        let lhsActivity = Self.activity(for: lhs, fallback: scannedAt)
        let rhsActivity = Self.activity(for: rhs, fallback: scannedAt)
        if lhsActivity != rhsActivity { return lhsActivity > rhsActivity }
        return lhs.id < rhs.id
    }

    private static func activity(for session: AgentSession, fallback: Date) -> Date {
        session.lastActivityAt ?? session.startedAt ?? fallback
    }

    private static func sanitizedLabel(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let leaf = URL(fileURLWithPath: value).lastPathComponent
        let normalized = leaf.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}
