import CodexBarCore
import Foundation

/// How a provider acquires credentials interactively, with everything the
/// coordinator needs to run it already resolved. Not `Equatable` — the OAuth
/// route carries its save closure; tests pattern-match instead.
public enum LoginRoute: Sendable {
    /// `save` folds the tokens into the provider's own store — the merge and
    /// 0600 logic from Tasks 4 and 5 — and nowhere else.
    case oauth(
        profile: OAuthProviderProfile,
        title: String,
        save: @Sendable (OAuthTokens) throws -> Void)
    case deviceFlow
    case embeddedCookie(CookieLoginEntry)
}

/// The single lookup behind the pane's "Sign in" button and the coordinator's
/// dispatch. Per-provider knowledge lives here as data; the generator and the
/// coordinator contain no provider switches (Global Constraints).
public enum LoginCatalog {
    private struct OAuthLogin: Sendable {
        let profile: OAuthProviderProfile
        let title: String
        let save: @Sendable (OAuthTokens) throws -> Void
    }

    /// OAuth providers with an obtainable Linux client. Gemini, Antigravity
    /// and Vertex AI are deliberately absent (discovery 4): their client
    /// credentials cannot be sourced on Linux, so there is nothing to verify
    /// a login against. M5 owns them — do not add them here.
    private static let oauthLogins: [UsageProvider: OAuthLogin] = [
        .claude: OAuthLogin(
            profile: ClaudeLogin.profile,
            title: "Sign in with Claude",
            save: { try ClaudeLogin.save(tokens: $0) }),
        .codex: OAuthLogin(
            profile: CodexLogin.profile,
            title: "Sign in with OpenAI",
            save: { try CodexLogin.save(tokens: $0) }),
    ]

    public static func route(for provider: UsageProvider) -> LoginRoute? {
        if let login = self.oauthLogins[provider] {
            return .oauth(profile: login.profile, title: login.title, save: login.save)
        }
        if provider == .copilot { return .deviceFlow }
        if let entry = ProviderLoginCatalog.entry(for: provider) {
            return .embeddedCookie(entry)
        }
        return nil
    }

    /// The label on the pane's button. `nil` exactly when `route(for:)` is.
    public static func buttonTitle(for provider: UsageProvider) -> String? {
        switch self.route(for: provider) {
        case let .oauth(_, title, _): title
        case .deviceFlow: "Sign in with GitHub"
        case .embeddedCookie: "Sign in…"
        case nil: nil
        }
    }
}
