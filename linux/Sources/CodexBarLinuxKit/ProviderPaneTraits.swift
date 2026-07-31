import CodexBarCore
import Foundation

/// The per-provider knowledge the generator cannot derive from
/// `ProviderDescriptor`. Data, not code: a provider added upstream works
/// without touching these tables, and gains the optional fields when its
/// id is added to the right set.
///
/// The provider membership lists mirror `CodexBarConfigValidation.swift`
/// (workspace/enterprise-host sets) and the region-validation list; they
/// change rarely upstream, and a sync that adds one is a one-line edit here.
public enum ProviderPaneTraits {
    /// Providers that accept a `region` field.
    public static let regionProviders: Set<UsageProvider> = [
        .minimax, .zai, .alibaba, .alibabatokenplan, .moonshot, .bedrock, .doubao,
    ]

    /// Providers that accept a `workspaceID` field.
    public static let workspaceProviders: Set<UsageProvider> = [
        .azureopenai, .openai, .opencode, .opencodego, .devin, .deepgram, .xai,
    ]

    /// Providers that accept an `enterpriseHost` field.
    public static let enterpriseHostProviders: Set<UsageProvider> = [
        .azureopenai, .clawrouter, .copilot, .kimi, .litellm, .llmproxy, .sub2api, .wayfinder,
    ]

    /// Providers whose credential pair includes a separate secret key.
    public static let secretKeyProviders: Set<UsageProvider> = [
        .bedrock, .doubao,
    ]

    /// Providers with an AWS profile/auth pair (Bedrock only today).
    public static let awsProfileProviders: Set<UsageProvider> = [
        .bedrock,
    ]

    /// Providers showing the `extrasEnabled` toggle (Codex's web extras).
    public static let extrasToggleProviders: Set<UsageProvider> = [
        .codex,
    ]

    public static let prioritizeExhaustedQuotaProviders: Set<UsageProvider> = [
        .antigravity,
    ]

    public static let profileScopeProviders: Set<UsageProvider> = [
        .deepseek,
    ]

    /// Canonical picker order for source modes. `sourceModes` is a Set, so
    /// without this the options would shuffle between launches.
    public static let sourceModeOrder: [ProviderSourceMode] = [
        .auto, .oauth, .cli, .api, .web,
    ]

    public static func sourceModeTitle(_ mode: ProviderSourceMode) -> String {
        switch mode {
        case .auto: "Auto"
        case .oauth: "OAuth"
        case .cli: "CLI"
        case .api: "API key"
        case .web: "Web (cookies)"
        }
    }
}
