import Foundation

/// Everything `OAuthLoginFlow` needs about one provider, as data.
///
/// Adding a provider is adding a value of this type; the flow itself never
/// learns a provider id.
public struct OAuthProviderProfile: Equatable, Sendable {
    /// How the authorization server hands the code back.
    public enum Redirect: Equatable, Sendable {
        /// A listener on `127.0.0.1`. Port 0 asks the kernel for a free one,
        /// which only works when the provider accepts any loopback port
        /// (RFC 8252 §7.3); providers that pre-register one exact URI need
        /// that port spelled out.
        case loopback(port: UInt16, path: String)
        /// The provider hosts the callback page and displays a code for the
        /// user to paste back into CodexBar.
        case hostedCode(url: String)
    }

    /// Token endpoints disagree about this and answer a bare 400 when it is
    /// wrong. Codex wants JSON (`CodexTokenRefresher.swift:50`), Claude wants
    /// form-urlencoded (`ClaudeOAuthCredentials.swift:1358`).
    public enum TokenEncoding: Equatable, Sendable {
        case form
        case json
    }

    public let providerID: String
    public let clientID: String
    public let authorizeURL: String
    public let tokenURL: String
    public let scopes: [String]
    public let redirect: Redirect
    public let tokenEncoding: TokenEncoding
    public let extraAuthorizeParameters: [String: String]

    /// Host written into a loopback `redirect_uri`. Ignored by `.hostedCode`.
    ///
    /// RFC 8252 §7.3 prefers the literal `127.0.0.1` because `localhost` can
    /// resolve elsewhere, but a provider that string-matches its registered
    /// URIs only accepts the spelling its own client sends — Claude's CLI binds
    /// `127.0.0.1` yet puts `localhost` in the `redirect_uri`. So this is data.
    public let loopbackHost: String

    /// Sent in the token request body when the flow has one. Claude's CLI
    /// echoes `state` there; providers that do not expect it ignore it.
    public let echoesStateInTokenRequest: Bool

    public init(
        providerID: String,
        clientID: String,
        authorizeURL: String,
        tokenURL: String,
        scopes: [String],
        redirect: Redirect,
        tokenEncoding: TokenEncoding,
        extraAuthorizeParameters: [String: String] = [:],
        loopbackHost: String = "127.0.0.1",
        echoesStateInTokenRequest: Bool = false)
    {
        self.loopbackHost = loopbackHost
        self.echoesStateInTokenRequest = echoesStateInTokenRequest
        self.providerID = providerID
        self.clientID = clientID
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.scopes = scopes
        self.redirect = redirect
        self.tokenEncoding = tokenEncoding
        self.extraAuthorizeParameters = extraAuthorizeParameters
    }
}
