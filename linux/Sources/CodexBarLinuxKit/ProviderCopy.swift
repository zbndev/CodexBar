import CodexBarCore
import Foundation

extension ProviderDescriptorRegistry {
    /// Descriptors whose only real usage source is the provider's web
    /// dashboard — the set the cookie login covers.
    ///
    /// Every descriptor carries `.auto` as well, so "web-only" is "nothing
    /// beyond auto and web". Testing `sourceModes.count == 1` matches nothing
    /// at all, which makes a walk-all test look like a guard while guarding
    /// nothing.
    public static var webOnly: [ProviderDescriptor] {
        self.all.filter { descriptor in
            let modes = descriptor.fetchPlan.sourceModes
            return modes.contains(.web) && modes.subtracting([.auto, .web]).isEmpty
        }
    }
}

/// A link attached to a provider's Links section — "Open Dashboard",
/// "Get API key". `Codable` because tests encode it; it never crosses the
/// bridge as its own row (the generator flattens it into `.link` rows).
public struct ProviderHelperLink: Codable, Equatable, Sendable {
    public var title: String
    public var url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

/// The per-provider words the generator cannot derive: what to paste into
/// the secret field, a line of guidance under it, and where to click for
/// help. Mined from the macOS provider implementations under
/// `Sources/CodexBar/Providers/**` — placeholders and subtitles come from
/// `ProviderSettingsFieldDescriptor`, links from the
/// `ProviderSettingsActionDescriptor` entries that open a static URL.
public struct ProviderCopyEntry: Equatable, Sendable {
    public var placeholder: String?
    public var hint: String?
    public var helperLinks: [ProviderHelperLink]

    public init(
        placeholder: String? = nil,
        hint: String? = nil,
        helperLinks: [ProviderHelperLink] = [])
    {
        self.placeholder = placeholder
        self.hint = hint
        self.helperLinks = helperLinks
    }
}

public enum ProviderCopy {
    /// `nil` for providers that need no guidance. The generator treats nil
    /// as "render exactly what M3 rendered".
    public static func entry(for provider: UsageProvider) -> ProviderCopyEntry? {
        self.entries[provider]
    }

    /// Alphabetical by provider id. A hint only renders under a cookie
    /// header field, so providers with no web source carry links and
    /// placeholders rather than dead prose.
    ///
    /// Four entries deliberately have no helper link — Alibaba Token Plan,
    /// Devin, Qoder and Qwen Cloud open a *computed* dashboard URL on macOS,
    /// which the generator's Links section already emits from
    /// `metadata.dashboardURL`.
    private static let entries: [UsageProvider: ProviderCopyEntry] = [
        .abacus: ProviderCopyEntry(
            placeholder: "Cookie: \u{2026}\n\nor paste a cURL capture from the Abacus AI dashboard",
            hint: "Automatic imports browser cookies.",
            helperLinks: [
                ProviderHelperLink(
                    title: "Open Dashboard",
                    url: "https://apps.abacus.ai/chatllm/admin/compute-points-usage"),
            ]),
        .alibabatokenplan: ProviderCopyEntry(
            placeholder: "Cookie: ...",
            hint: "Automatic imports browser cookies from Model Studio/Bailian."),
        .claude: ProviderCopyEntry(
            // No placeholder: Claude has both an API key and a cookie field,
            // and one string cannot honestly label both.
            hint: "Automatic imports browser cookies for the web API."),
        .codex: ProviderCopyEntry(
            placeholder: "Cookie: \u{2026}",
            hint: "Automatic imports browser cookies for dashboard extras."),
        .commandcode: ProviderCopyEntry(
            placeholder: "Cookie: \u{2026}",
            hint: "Automatic imports browser cookies.",
            helperLinks: [
                ProviderHelperLink(
                    title: "Open Command Code Settings",
                    url: "https://commandcode.ai/studio"),
            ]),
        .copilot: ProviderCopyEntry(
            // Copilot has no web source row, so a hint would never render.
            // The budgets page is where the manual header comes from
            // (docs/copilot.md).
            helperLinks: [
                ProviderHelperLink(
                    title: "Open GitHub billing budgets",
                    url: "https://github.com/settings/billing/budgets"),
            ]),
        .cursor: ProviderCopyEntry(
            hint: "Automatic imports browser cookies or stored sessions."),
        .devin: ProviderCopyEntry(
            // Devin's manual credential is a bearer token, not a cookie.
            placeholder: "Bearer eyJ...",
            hint: "Paste the Authorization header value from app.devin.ai."),
        .longcat: ProviderCopyEntry(
            placeholder: "Cookie: \u{2026}",
            hint: "Automatic imports longcat.chat cookies from your browser.",
            helperLinks: [
                ProviderHelperLink(title: "Open Console", url: "https://longcat.chat/platform/"),
            ]),
        .manus: ProviderCopyEntry(
            placeholder: "session_id=...\n\nor paste just the session_id value",
            hint: "Automatically imports browser session cookies.",
            helperLinks: [
                ProviderHelperLink(title: "Open Manus", url: "https://manus.im"),
            ]),
        .mimo: ProviderCopyEntry(
            placeholder: "Cookie: ...",
            hint: "Automatic imports browser cookies from Xiaomi MiMo.",
            helperLinks: [
                ProviderHelperLink(
                    title: "Open MiMo Balance",
                    url: "https://platform.xiaomimimo.com/#/console/balance"),
            ]),
        .mistral: ProviderCopyEntry(
            placeholder: "ory_session_\u{2026}=\u{2026}; csrftoken=\u{2026}",
            hint: "Paste the Cookie header from a request to admin.mistral.ai. "
                + "Must contain an ory_session_* cookie.",
            helperLinks: [
                ProviderHelperLink(
                    title: "Open Mistral Admin",
                    url: "https://admin.mistral.ai/organization/usage"),
            ]),
        .notion: ProviderCopyEntry(
            placeholder: "token_v2=\u{2026}",
            hint: "Paste the Cookie header from a request to app.notion.com. "
                + "Must contain a token_v2 cookie.",
            helperLinks: [
                ProviderHelperLink(
                    title: "Open Notion",
                    url: "https://app.notion.com/"),
            ]),
        .openai: ProviderCopyEntry(
            placeholder: "sk-admin-...",
            helperLinks: [
                ProviderHelperLink(
                    title: "Open billing",
                    url: "https://platform.openai.com/settings/organization/billing/overview"),
                ProviderHelperLink(
                    title: "Open projects",
                    url: "https://platform.openai.com/settings/organization/projects"),
            ]),
        .opencode: ProviderCopyEntry(
            hint: "Automatic imports browser cookies from opencode.ai."),
        .opencodego: ProviderCopyEntry(
            hint: "Automatic imports browser cookies from opencode.ai."),
        .perplexity: ProviderCopyEntry(
            placeholder: "Cookie: \u{2026}\n\nor paste the __Secure-next-auth.session-token value",
            hint: "Automatically imports browser session cookie.",
            helperLinks: [
                ProviderHelperLink(
                    title: "Open Usage Page",
                    url: "https://www.perplexity.ai/account/usage"),
            ]),
        .qoder: ProviderCopyEntry(
            placeholder: "Cookie: \u{2026}\n\nor paste a cURL capture from the Qoder usage page",
            hint: "Automatic imports browser cookies."),
        .qwencloud: ProviderCopyEntry(
            placeholder: "Cookie: ...",
            hint: "Automatic imports browser cookies from Qwen Cloud."),
        .sakana: ProviderCopyEntry(
            placeholder: "Cookie: ...",
            hint: "Paste the Cookie header from a signed-in console.sakana.ai session.",
            helperLinks: [
                ProviderHelperLink(
                    title: "Open Sakana AI Console",
                    url: "https://console.sakana.ai/billing"),
            ]),
        .stepfun: ProviderCopyEntry(
            placeholder: "Oasis-Token=\u{2026}",
            hint: "Paste the Oasis-Token from a logged-in browser session on platform.stepfun.com.",
            helperLinks: [
                ProviderHelperLink(
                    title: "Open StepFun Platform",
                    url: "https://platform.stepfun.com/plan-usage"),
            ]),
        .t3chat: ProviderCopyEntry(
            placeholder: "Cookie: ...",
            hint: "Paste a Cookie header or full cURL capture from T3 Chat settings.",
            helperLinks: [
                ProviderHelperLink(
                    title: "Open T3 Chat Settings",
                    url: "https://t3.chat/settings/customization"),
            ]),
        .zoommate: ProviderCopyEntry(
            placeholder:
            "curl 'https://ai.zoom.us/ai-computer/api/v1/credits/status' -H 'authorization: ...'",
            hint: "Paste a full cURL capture from the ZoomMate AI credit usage page. "
                + "The token expires approximately hourly, so you may need to re-paste periodically.",
            helperLinks: [
                ProviderHelperLink(
                    title: "Open ZoomMate",
                    url: "https://zoommate.zoom.us/#/?settings=credit-usage"),
            ]),
    ]
}
