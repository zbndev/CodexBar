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
        sourceMode: ProviderSourceMode) async -> Result<ProviderFetchResult, Error>
    {
        let browserDetection = BrowserDetection()
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: sourceMode,
            includeCredits: true,
            webTimeout: 15,
            webDebugDumpHTML: false,
            verbose: false,
            env: self.environment,
            settings: nil,
            fetcher: UsageFetcher(environment: self.environment),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection,
            // The GUI is long-lived, so warm CLI helper sessions may outlive
            // a single fetch, matching how the menu bar app and `serve` behave.
            persistsCLISessions: true,
            persistentCLISessionIdleWindow: 300)

        let outcome = await descriptor.fetchPlan.pipeline.fetch(
            context: context,
            provider: descriptor.id)
        return outcome.result
    }

    /// The source mode to use for a provider: whatever the config pins, else auto.
    public static func sourceMode(
        for provider: UsageProvider,
        config: CodexBarConfig?) -> ProviderSourceMode
    {
        config?.providers.first { $0.id == provider }?.source ?? .auto
    }
}
