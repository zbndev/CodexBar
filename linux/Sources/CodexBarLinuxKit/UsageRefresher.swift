import CodexBarCore
import Foundation

/// Fetches one provider through its descriptor's own strategy pipeline.
///
/// This is the single reason the GUI needs no per-provider fetch code: the
/// pipeline already encodes each provider's source order and fallbacks.
public struct UsageRefresher: Sendable {
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func fetch(
        descriptor: ProviderDescriptor,
        sourceMode: ProviderSourceMode,
        config: ProviderConfig? = nil,
        settings: ProviderSettingsSnapshot? = nil) async -> Result<ProviderFetchResult, Error>
    {
        let context = Self.makeContext(
            descriptor: descriptor,
            sourceMode: sourceMode,
            environment: Self.resolvedEnvironment(
                base: self.environment,
                provider: descriptor.id,
                config: config),
            settings: settings)

        let outcome = await descriptor.fetchPlan.pipeline.fetch(
            context: context,
            provider: descriptor.id)
        return outcome.result
    }

    /// Split out so a test can assert that a strategy accepts the context this
    /// builds, rather than only that the pieces look right.
    public static func makeContext(
        descriptor: ProviderDescriptor,
        sourceMode: ProviderSourceMode,
        environment: [String: String],
        settings: ProviderSettingsSnapshot?) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection()
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: sourceMode,
            includeCredits: true,
            webTimeout: 15,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: settings,
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection,
            // The GUI is long-lived, so warm CLI helper sessions may outlive
            // a single fetch, matching how the menu bar app and `serve` behave.
            persistsCLISessions: true,
            persistentCLISessionIdleWindow: 300)
    }

    /// Folds the provider's stored config into the environment the strategies
    /// actually read.
    ///
    /// Most credentials never reach a strategy as config: `ZaiSettingsReader`
    /// looks at `Z_AI_API_KEY`, `KimiSettingsReader` at `KIMI_API_KEY`, and so
    /// on. Core projects the saved `apiKey`, cookie header and enterprise host
    /// onto those variables here — the same call the CLI makes before every
    /// fetch. Skipping it makes every strategy report itself unavailable, and
    /// the pipeline then fails the provider with `noAvailableStrategy`.
    public static func resolvedEnvironment(
        base: [String: String],
        provider: UsageProvider,
        config: ProviderConfig?) -> [String: String]
    {
        ProviderEnvironmentResolver.resolve(
            base: base,
            provider: provider,
            config: config,
            selectedAccount: self.activeTokenAccount(config))
    }

    /// The token account a fetch should authenticate as, or nil when the
    /// provider stores none. `activeIndex` is clamped rather than trusted: it
    /// is persisted alongside the list and can outlive a removal.
    public static func activeTokenAccount(_ config: ProviderConfig?) -> ProviderTokenAccount? {
        guard let data = config?.tokenAccounts, !data.accounts.isEmpty else { return nil }
        let index = min(max(data.activeIndex, 0), data.accounts.count - 1)
        return data.accounts[index]
    }

    /// The source mode to use for a provider: whatever the config pins, else auto.
    public static func sourceMode(
        for provider: UsageProvider,
        config: CodexBarConfig?) -> ProviderSourceMode
    {
        config?.providers.first { $0.id == provider }?.source ?? .auto
    }
}
