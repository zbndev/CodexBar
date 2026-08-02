import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

@Suite
struct LinuxAgentSessionsStoreTests {
    @Test func `refresh sorts active sessions first and collapses duplicate ids`() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = LinuxAgentSessionsStore(scan: { _, _, _ in
            [
                Self.session(id: "idle", state: .idle, activity: now.addingTimeInterval(-20)),
                Self.session(id: "duplicate", state: .idle, activity: now.addingTimeInterval(-10)),
                Self.session(id: "duplicate", state: .active, activity: now.addingTimeInterval(-30)),
                Self.session(id: "active", state: .active, activity: now.addingTimeInterval(-5)),
            ]
        })

        let payload = await store.refresh(now: now)

        #expect(payload.sessions.map(\.id) == ["active", "duplicate", "idle"])
        #expect(payload.sessions.map(\.state) == ["active", "active", "idle"])
    }

    @Test func `agent session views never contain scanner-only fields`() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = LinuxAgentSessionsStore(scan: { _, _, _ in
            [Self.session(id: "fixture", state: .active, activity: now)]
        })

        let payload = await store.refresh(now: now)
        let text = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)

        #expect(!text.contains("/home/fixture/private-project"))
        #expect(!text.contains("/tmp/fixture-transcript.jsonl"))
        #expect(!text.contains("4242"))
        #expect(!text.contains("fixture-host"))
        #expect(payload.sessions == [AgentSessionView(
            id: "fixture",
            provider: "codex",
            state: "active",
            projectName: "private-project",
            sessionName: "fixture session",
            lastActivityAt: now)])
    }

    @Test func `concurrent refresh calls run the scanner once`() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let scanner = BlockingScanner(result: [Self.session(id: "fixture", state: .active, activity: now)])
        let joined = RefreshJoin()
        let store = LinuxAgentSessionsStore(
            scan: { _, _, _ in await scanner.scan() },
            onRefreshJoin: { await joined.record() })

        let first = Task { await store.refresh(now: now) }
        await scanner.waitUntilStarted()
        let second = Task { await store.refresh(now: now) }
        await joined.wait()
        await scanner.release()

        _ = await first.value
        _ = await second.value
        #expect(await scanner.callCount() == 1)
    }

    private static func session(
        id: String,
        state: AgentSession.State,
        activity: Date) -> AgentSession
    {
        AgentSession(
            id: id,
            provider: .codex,
            source: .cli,
            state: state,
            pid: 4242,
            cwd: "/home/fixture/private-project",
            projectName: "/home/fixture/private-project",
            sessionName: "fixture session",
            startedAt: activity.addingTimeInterval(-60),
            lastActivityAt: activity,
            transcriptPath: "/tmp/fixture-transcript.jsonl",
            host: "fixture-host")
    }
}

private actor BlockingScanner {
    private let result: [AgentSession]
    private var calls = 0
    private var started: CheckedContinuation<Void, Never>?
    private var releaseScan: CheckedContinuation<Void, Never>?

    init(result: [AgentSession]) {
        self.result = result
    }

    func scan() async -> [AgentSession] {
        self.calls += 1
        self.started?.resume()
        self.started = nil
        await withCheckedContinuation { continuation in
            self.releaseScan = continuation
        }
        return self.result
    }

    func waitUntilStarted() async {
        if self.calls > 0 { return }
        await withCheckedContinuation { continuation in
            self.started = continuation
        }
    }

    func release() {
        self.releaseScan?.resume()
        self.releaseScan = nil
    }

    func callCount() -> Int {
        self.calls
    }
}

private actor RefreshJoin {
    private var continuation: CheckedContinuation<Void, Never>?

    func record() {
        self.continuation?.resume()
        self.continuation = nil
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}
