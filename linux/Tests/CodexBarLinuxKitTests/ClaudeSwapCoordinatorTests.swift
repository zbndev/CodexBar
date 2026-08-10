import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private final class ClaudeSwapCallTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        self.lock.withLock { self.values.append(value) }
    }

    func snapshot() -> [String] {
        self.lock.withLock { self.values }
    }
}

private func claudeSwapFixtureAccount(number: Int = 1, isActive: Bool = true) -> CodexBarCore.ClaudeSwapAccountRow {
    CodexBarCore.ClaudeSwapAccountRow(
        number: number,
        email: "fixture-account@example.test",
        isActive: isActive,
        usageStatus: .ok,
        fiveHour: nil,
        sevenDay: nil)
}

@Test
func `configured executable takes precedence over PATH and absent PATH is reported safely`() async {
    var configured = ProviderConfig(id: .claude)
    configured.claudeSwapEnabled = true
    configured.claudeSwapExecutablePath = "configured-fixture"
    var pathOnly = ProviderConfig(id: .claude)
    pathOnly.claudeSwapEnabled = true
    let trace = ClaudeSwapCallTrace()
    let coordinator = ClaudeSwapCoordinator(
        configuredPathResolver: { value in
            trace.append("configured:\(value)")
            return value
        },
        pathLookup: {
            trace.append("PATH")
            return "path-fixture"
        },
        readAccountList: { executable in
            trace.append("read:\(executable)")
            return ClaudeSwapAccountList(
                activeAccountNumber: 1,
                accounts: [claudeSwapFixtureAccount()])
        },
        switchAccount: { _, _ in
            Issue.record("switch is not expected in this test")
            return ClaudeSwapAccountSwitchResult(
                switched: true,
                fromAccountNumber: nil,
                toAccountNumber: 1,
                reason: "fixture")
        })

    let configuredPayload = await coordinator.refresh(config: configured)
    #expect(configuredPayload.executablePath == "configured-fixture")
    #expect(configuredPayload.errorMessage == nil)
    #expect(trace.snapshot() == ["configured:configured-fixture", "read:configured-fixture"])

    let pathPayload = await coordinator.refresh(config: pathOnly)
    #expect(pathPayload.executablePath == "path-fixture")
    #expect(pathPayload.errorMessage == nil)
    #expect(trace.snapshot() == [
        "configured:configured-fixture", "read:configured-fixture", "PATH", "read:path-fixture",
    ])

    let absentCoordinator = ClaudeSwapCoordinator(
        configuredPathResolver: { $0 },
        pathLookup: { nil },
        readAccountList: { _ in
            Issue.record("an absent executable must not be read")
            return ClaudeSwapAccountList(activeAccountNumber: nil, accounts: [])
        },
        switchAccount: { _, _ in
            Issue.record("an absent executable must not be switched")
            return ClaudeSwapAccountSwitchResult(
                switched: false,
                fromAccountNumber: nil,
                toAccountNumber: 1,
                reason: "fixture")
        })
    let absentPayload = await absentCoordinator.refresh(config: pathOnly)
    #expect(absentPayload.executablePath == nil)
    #expect(absentPayload.errorMessage == "claude-swap executable not found.")
}

@Test
func `a successful switch re-reads accounts before publishing`() async {
    let trace = ClaudeSwapCallTrace()
    let coordinator = ClaudeSwapCoordinator(
        configuredPathResolver: { $0 },
        pathLookup: { nil },
        readAccountList: { executable in
            trace.append("read:\(executable)")
            return ClaudeSwapAccountList(
                activeAccountNumber: 2,
                accounts: [claudeSwapFixtureAccount(number: 2)])
        },
        switchAccount: { executable, number in
            trace.append("switch:\(executable):\(number)")
            return ClaudeSwapAccountSwitchResult(
                switched: true,
                fromAccountNumber: 1,
                toAccountNumber: number,
                reason: "fixture")
        })
    var config = ProviderConfig(id: .claude)
    config.claudeSwapEnabled = true
    config.claudeSwapExecutablePath = "configured-fixture"

    await coordinator.switchAccount(number: 2, config: config) { payload in
        trace.append("publish")
        #expect(payload.accounts.map(\.number) == [2])
        #expect(payload.accounts.first?.isActive == true)
    }

    #expect(trace.snapshot() == [
        "switch:configured-fixture:2", "read:configured-fixture", "publish",
    ])
}
