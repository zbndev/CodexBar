import CodexBarCore
import Foundation

public struct ExternalCredentialLoginEntry: Sendable {
    public let provider: UsageProvider
    public let title: String
    public let executableCandidates: [String]
    public let arguments: [String]
    public let helpURL: URL
    public let readiness: @Sendable () async -> ExternalCredentialReadiness

    public init(
        provider: UsageProvider,
        title: String,
        executableCandidates: [String],
        arguments: [String],
        helpURL: URL,
        readiness: @escaping @Sendable () async -> ExternalCredentialReadiness)
    {
        self.provider = provider
        self.title = title
        self.executableCandidates = executableCandidates
        self.arguments = arguments
        self.helpURL = helpURL
        self.readiness = readiness
    }

    var command: String {
        ([self.executableCandidates[0]] + self.arguments).joined(separator: " ")
    }
}

public enum ExternalCredentialReadiness: Equatable, Sendable {
    case unavailable(executable: String)
    case waiting
    case ready
}

public enum ExternalCredentialLogin {
    public static let catalog: [UsageProvider: ExternalCredentialLoginEntry] = [
        .gemini: ExternalCredentialLoginEntry(
            provider: .gemini,
            title: "Sign in with Gemini CLI",
            executableCandidates: ["gemini"],
            arguments: [],
            helpURL: URL(string: "https://google-gemini.github.io/gemini-cli/docs/get-started/authentication.html")!,
            readiness: { await Self.geminiReadiness() }),
        .antigravity: ExternalCredentialLoginEntry(
            provider: .antigravity,
            title: "Sign in with Antigravity CLI",
            executableCandidates: ["antigravity"],
            arguments: [],
            helpURL: URL(string: "https://github.com/google-antigravity/antigravity-cli#authentication")!,
            readiness: { await Self.antigravityReadiness() }),
        .vertexai: ExternalCredentialLoginEntry(
            provider: .vertexai,
            title: "Sign in with gcloud",
            executableCandidates: ["gcloud"],
            arguments: ["auth", "application-default", "login"],
            helpURL: URL(string: "https://docs.cloud.google.com/docs/authentication/application-default-credentials")!,
            readiness: { await Self.vertexReadiness() }),
    ]

    private static func geminiReadiness() async -> ExternalCredentialReadiness {
        let environment = ProcessInfo.processInfo.environment
        return await self.geminiReadiness(
            environment: environment,
            coreStrategyAvailable: { environment in
                await self.coreStrategyIsAvailable(for: .gemini, environment: environment)
            })
    }

    static func geminiReadiness(
        environment: [String: String],
        coreStrategyAvailable: @escaping @Sendable ([String: String]) async -> Bool) async -> ExternalCredentialReadiness
    {
        if let apiKey = environment["GEMINI_API_KEY"], !apiKey.isEmpty {
            return .ready
        }
        if await coreStrategyAvailable(environment) {
            return .ready
        }
        guard SystemTerminal.isExecutableAvailable("gemini", environment: environment) else {
            return .unavailable(executable: "gemini")
        }
        return .waiting
    }

    private static func antigravityReadiness() async -> ExternalCredentialReadiness {
        let environment = ProcessInfo.processInfo.environment
        return await self.antigravityReadiness(
            environment: environment,
            coreStrategyAvailable: { environment in
                await self.coreStrategyIsAvailable(for: .antigravity, environment: environment)
            })
    }

    static func antigravityReadiness(
        environment: [String: String],
        coreStrategyAvailable: @escaping @Sendable ([String: String]) async -> Bool) async -> ExternalCredentialReadiness
    {
        guard SystemTerminal.isExecutableAvailable("antigravity", environment: environment) else {
            return .unavailable(executable: "antigravity")
        }
        return await coreStrategyAvailable(environment) ? .ready : .waiting
    }

    private static func vertexReadiness() async -> ExternalCredentialReadiness {
        await self.vertexReadiness(environment: ProcessInfo.processInfo.environment)
    }

    static func vertexReadiness(environment: [String: String]) async -> ExternalCredentialReadiness {
        let fileManager = FileManager.default
        if let configuredPath = environment["GOOGLE_APPLICATION_CREDENTIALS"],
           fileManager.isReadableFile(atPath: configuredPath)
        {
            return .ready
        }
        let home = environment["HOME"] ?? fileManager.homeDirectoryForCurrentUser.path
        let adcURL = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".config/gcloud/application_default_credentials.json")
        guard !fileManager.isReadableFile(atPath: adcURL.path) else { return .ready }
        return SystemTerminal.isExecutableAvailable("gcloud", environment: environment)
            ? .waiting
            : .unavailable(executable: "gcloud")
    }

    private static func coreStrategyIsAvailable(
        for provider: UsageProvider,
        environment: [String: String]) async -> Bool
    {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let context = UsageRefresher.makeContext(
            descriptor: descriptor,
            sourceMode: .auto,
            environment: environment,
            settings: nil)
        let strategies = await descriptor.fetchPlan.pipeline.resolveStrategies(context)
        for strategy in strategies {
            if await strategy.isAvailable(context) {
                return true
            }
        }
        return false
    }
}
