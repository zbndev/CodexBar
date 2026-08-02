import CodexBarCore
import Foundation

/// Display-only account information safe to pass across the settings bridge.
public struct ClaudeSwapAccountRow: Codable, Equatable, Sendable {
    public let number: Int
    public let email: String
    public let isActive: Bool
    public let status: String

    public init(number: Int, email: String, isActive: Bool, status: String) {
        self.number = number
        self.email = email
        self.isActive = isActive
        self.status = status
    }

    init(_ account: CodexBarCore.ClaudeSwapAccountRow) {
        self.init(
            number: account.number,
            email: account.email,
            isActive: account.isActive,
            status: Self.displayStatus(for: account.usageStatus))
    }

    private static func displayStatus(for status: ClaudeSwapUsageStatus) -> String {
        switch status {
        case .ok:
            "Ready"
        case .tokenExpired, .reloginRequired:
            "Sign-in required"
        case .apiKey:
            "API key"
        case .keychainUnavailable:
            "Keychain unavailable"
        case .noCredentials:
            "No credentials"
        case .unavailable, .unknown:
            "Unavailable"
        }
    }
}

/// The claude-swap portion of a settings payload. It deliberately contains no
/// command output, credentials, or parser errors.
public struct ClaudeSwapPayload: Codable, Equatable, Sendable {
    public let executablePath: String?
    public let accounts: [ClaudeSwapAccountRow]
    public let errorMessage: String?

    public init(executablePath: String?, accounts: [ClaudeSwapAccountRow], errorMessage: String?) {
        self.executablePath = executablePath
        self.accounts = accounts
        self.errorMessage = errorMessage
    }
}

/// Discovers and invokes the opt-in claude-swap adapter using only Core's fixed
/// argument vectors. The coordinator translates all failures into safe display
/// messages before the settings bridge receives them.
public struct ClaudeSwapCoordinator: Sendable {
    private let configuredPathResolver: @Sendable (String) throws -> String
    private let pathLookup: @Sendable () -> String?
    private let readAccountList: @Sendable (String) async throws -> ClaudeSwapAccountList
    private let switchAccount: @Sendable (String, Int) async throws -> ClaudeSwapAccountSwitchResult

    public init(
        configuredPathResolver: @escaping @Sendable (String) throws -> String = {
            try ClaudeSwapAccountReader.resolvedExecutablePath($0)
        },
        pathLookup: @escaping @Sendable () -> String? = Self.lookupOnPath,
        readAccountList: @escaping @Sendable (String) async throws -> ClaudeSwapAccountList = {
            try await ClaudeSwapAccountReader.readAccountList(executablePath: $0)
        },
        switchAccount: @escaping @Sendable (String, Int) async throws -> ClaudeSwapAccountSwitchResult = {
            try await ClaudeSwapAccountReader.switchAccount(executablePath: $0, accountNumber: $1)
        })
    {
        self.configuredPathResolver = configuredPathResolver
        self.pathLookup = pathLookup
        self.readAccountList = readAccountList
        self.switchAccount = switchAccount
    }

    public func refresh(config: ProviderConfig?) async -> ClaudeSwapPayload {
        guard let executablePath = self.executablePath(config: config) else {
            return ClaudeSwapPayload(
                executablePath: nil,
                accounts: [],
                errorMessage: config?.claudeSwapEnabled == true ? "claude-swap executable not found." : nil)
        }

        do {
            let list = try await self.readAccountList(executablePath)
            return ClaudeSwapPayload(
                executablePath: executablePath,
                accounts: list.accounts.map(ClaudeSwapAccountRow.init),
                errorMessage: nil)
        } catch {
            return ClaudeSwapPayload(
                executablePath: executablePath,
                accounts: [],
                errorMessage: "Could not read claude-swap accounts.")
        }
    }

    /// Publishes exactly once. A successful credential transaction always
    /// reads the new list before the publisher can receive updated state.
    public func switchAccount(
        number: Int,
        config: ProviderConfig?,
        publish: @escaping @Sendable (ClaudeSwapPayload) -> Void) async
    {
        guard number > 0, let executablePath = self.executablePath(config: config) else {
            publish(ClaudeSwapPayload(
                executablePath: nil,
                accounts: [],
                errorMessage: "claude-swap executable not found."))
            return
        }

        do {
            let result = try await self.switchAccount(executablePath, number)
            guard result.switched else {
                publish(ClaudeSwapPayload(
                    executablePath: executablePath,
                    accounts: [],
                    errorMessage: "Could not switch claude-swap account."))
                return
            }
            publish(await self.refresh(config: config))
        } catch {
            publish(ClaudeSwapPayload(
                executablePath: executablePath,
                accounts: [],
                errorMessage: "Could not switch claude-swap account."))
        }
    }

    private func executablePath(config: ProviderConfig?) -> String? {
        guard config?.claudeSwapEnabled == true else { return nil }
        if let configuredPath = config?.sanitizedClaudeSwapExecutablePath {
            return try? self.configuredPathResolver(configuredPath)
        }
        return self.pathLookup()
    }

    public static func lookupOnPath() -> String? {
        let directories = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? []
        for directory in directories {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent("claude-swap")
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

public final class ClaudeSwapState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ClaudeSwapPayload

    public init(payload: ClaudeSwapPayload = ClaudeSwapPayload(
        executablePath: nil,
        accounts: [],
        errorMessage: nil))
    {
        self.value = payload
    }

    public func payload() -> ClaudeSwapPayload {
        self.lock.withLock { self.value }
    }

    public func replace(_ payload: ClaudeSwapPayload) {
        self.lock.withLock { self.value = payload }
    }
}
