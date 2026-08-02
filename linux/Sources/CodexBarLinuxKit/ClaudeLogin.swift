import CodexBarCore
import Foundation

/// Claude's OAuth profile and the writer that puts its tokens where Core
/// already looks for them.
///
/// On macOS Core prefers the keychain and falls back to the file; on Linux the
/// keychain branches are `#if os(macOS)`, so the file is the only path and
/// this writer is the whole story.
public enum ClaudeLogin {
    /// Endpoints, scopes and redirect policy measured from the installed
    /// Claude CLI (`~/.local/share/claude/versions/2.1.220`); the client id
    /// comes from Core so an upstream change to it propagates on sync.
    ///
    /// The CLI builds both an `isManual` and a loopback authorize URL and
    /// exchanges whichever one actually answered, so the authorization server
    /// accepts loopback redirects on an arbitrary ephemeral port. Its listener
    /// binds `127.0.0.1` on port 0 but spells the `redirect_uri` host
    /// `localhost`, and this profile copies that spelling exactly rather than
    /// assume the server normalizes the two.
    ///
    /// `tokenEncoding` is `.json`: the CLI posts the authorization_code grant
    /// as JSON. Core's form-urlencoded request
    /// (`ClaudeOAuthCredentials.swift:1358`) is the *refresh_token* grant — a
    /// different call with a different encoding.
    public static let profile = OAuthProviderProfile(
        providerID: "claude",
        clientID: ClaudeOAuthCredentialsStore.defaultOAuthClientID,
        authorizeURL: "https://platform.claude.com/oauth/authorize",
        tokenURL: "https://platform.claude.com/v1/oauth/token",
        scopes: ["org:create_api_key", "user:profile", "user:inference"],
        redirect: .loopback(port: 0, path: "/callback"),
        tokenEncoding: .json,
        extraAuthorizeParameters: ["code": "true"],
        loopbackHost: "localhost",
        echoesStateInTokenRequest: true)

    public static func credentialsURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL
    {
        ClaudeConfigPaths.credentialsURL(environment: environment)
    }

    /// Folds new tokens into whatever the file already holds.
    ///
    /// Merge rather than overwrite for two reasons: the file can carry a
    /// sibling `mcpOAuth` block (`ClaudeOAuthCredentialModels.swift:94`) that
    /// belongs to Claude Code's MCP state, and the previous `claudeAiOauth`
    /// may hold `subscriptionType`/`rateLimitTier` — values the token endpoint
    /// does not return but the usage fetcher reads.
    public static func merge(tokens: OAuthTokens, into existing: Data?, now: Date) throws -> Data {
        var root: [String: Any] = [:]
        if let existing,
           let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any]
        {
            root = parsed
        }
        var oauth = root["claudeAiOauth"] as? [String: Any] ?? [:]

        oauth["accessToken"] = tokens.accessToken
        if let refreshToken = tokens.refreshToken { oauth["refreshToken"] = refreshToken }
        if let expiresIn = tokens.expiresIn {
            // Core divides by 1000 on read (ClaudeOAuthCredentialModels.swift:113).
            oauth["expiresAt"] = now.addingTimeInterval(TimeInterval(expiresIn))
                .timeIntervalSince1970 * 1000
        }
        if let scope = tokens.scope {
            oauth["scopes"] = scope.split(separator: " ").map(String.init)
        }

        root["claudeAiOauth"] = oauth
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    public static func save(
        tokens: OAuthTokens,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()) throws
    {
        let url = self.credentialsURL(environment: environment)
        let existing = try? Data(contentsOf: url)
        let merged = try self.merge(tokens: tokens, into: existing, now: now)
        try PrivateFileWriter.write(merged, to: url)
    }
}
