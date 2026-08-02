import CodexBarCore
import Foundation

/// Codex's OAuth profile and the mapping onto Core's `auth.json` writer.
///
/// Unlike Claude, no new writer is needed:
/// `CodexOAuthCredentialsStore.save(_:env:)` is public, already writes 0600
/// through a staged rename, and already preserves the other keys `auth.json`
/// may hold (notably `OPENAI_API_KEY`).
public enum CodexLogin {
    /// Where the usage fetcher expects the account id to have come from
    /// (`CodexOAuthUsageFetcher.swift:376` sends it as `ChatGPT-Account-Id`).
    private static let accountClaimPath = ["https://api.openai.com/auth"]
    private static let accountClaimKey = "chatgpt_account_id"

    /// Measured 2026-08-02 by starting `codex login` and reading both what it
    /// bound and the URL it printed:
    ///
    ///     Starting local login server on http://localhost:1455.
    ///     …redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback…
    ///     ss: LISTEN 127.0.0.1:1455 users:(("codex",…))
    ///
    /// So the port is 1455 — the documented default, now confirmed rather than
    /// assumed — and the `redirect_uri` host is spelled `localhost` even though
    /// the listener binds `127.0.0.1`.
    public static let profile = OAuthProviderProfile(
        providerID: "codex",
        clientID: "app_EMoamEEZ73f0CkXaXp7hrann",
        authorizeURL: "https://auth.openai.com/oauth/authorize",
        tokenURL: "https://auth.openai.com/oauth/token",
        // openid/profile/email match the refresh scope Core uses; offline_access
        // is what makes the token endpoint return a refresh_token at all. The
        // CLI also asks for api.connectors.read/invoke, deliberately dropped:
        // CodexBar only reads usage and has no use for connector access.
        scopes: ["openid", "profile", "email", "offline_access"],
        // Exact-match registration: the port is fixed, never ephemeral.
        redirect: .loopback(port: 1455, path: "/auth/callback"),
        tokenEncoding: .json,
        // id_token_add_organizations is load-bearing — it is what puts the
        // https://api.openai.com/auth block, and so chatgpt_account_id, into
        // the id token that `accountID(from:)` reads. `originator` is sent
        // because the server may condition this client id's behaviour on it.
        // The CLI's codex_cli_simplified_flow is a UI variant and is omitted.
        extraAuthorizeParameters: [
            "id_token_add_organizations": "true",
            "originator": "codex_cli_rs",
        ],
        loopbackHost: "localhost")

    /// The account id, preferring an explicit response field and falling back
    /// to the id token's claim — which is where Codex actually puts it.
    public static func accountID(from tokens: OAuthTokens) -> String? {
        if let explicit = tokens.accountID, !explicit.isEmpty { return explicit }
        guard let idToken = tokens.idToken else { return nil }
        return JWTClaims.string(
            self.accountClaimKey,
            path: self.accountClaimPath,
            inIDToken: idToken)
    }

    public static func save(
        tokens: OAuthTokens,
        environment: [String: String] = ProcessInfo.processInfo.environment) throws
    {
        let credentials = CodexOAuthCredentials(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken ?? "",
            idToken: tokens.idToken,
            accountId: self.accountID(from: tokens),
            // save() stamps last_refresh itself; this value is not persisted.
            lastRefresh: Date())
        try CodexOAuthCredentialsStore.save(credentials, env: environment)
    }
}
