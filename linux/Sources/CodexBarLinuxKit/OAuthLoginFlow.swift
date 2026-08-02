import CodexBarCore
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The tokens an authorization server returns. Kept provider-neutral; each
/// provider's writer maps it onto whatever file Core reads.
public struct OAuthTokens: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let expiresIn: Int?
    public let scope: String?
    /// Only some providers return one; Codex carries it inside the id token.
    public let accountID: String?

    public init(
        accessToken: String,
        refreshToken: String?,
        idToken: String?,
        expiresIn: Int?,
        scope: String?,
        accountID: String? = nil)
    {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.expiresIn = expiresIn
        self.scope = scope
        self.accountID = accountID
    }

    public static func parse(_ data: Data) throws -> OAuthTokens {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoginError.malformedTokenResponse("not a JSON object")
        }
        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw LoginError.malformedTokenResponse("no access_token")
        }
        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            idToken: json["id_token"] as? String,
            expiresIn: json["expires_in"] as? Int,
            scope: json["scope"] as? String,
            accountID: json["account_id"] as? String)
    }

    /// Copy with an account id recovered from elsewhere (an id-token claim).
    public func withAccountID(_ accountID: String?) -> OAuthTokens {
        OAuthTokens(
            accessToken: self.accessToken,
            refreshToken: self.refreshToken,
            idToken: self.idToken,
            expiresIn: self.expiresIn,
            scope: self.scope,
            accountID: accountID ?? self.accountID)
    }
}

/// Reads claims out of an unverified id token.
///
/// Unverified is correct here: the token arrived over TLS directly from the
/// token endpoint in response to our own request, so there is no third party
/// to authenticate it against. It is used only to recover an account id for a
/// request header — never as an authorization decision.
public enum JWTClaims {
    public static func string(_ key: String, path: [String], inIDToken token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2,
              let payload = self.decodeBase64URL(String(segments[1])),
              var object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else {
            return nil
        }
        for component in path {
            guard let nested = object[component] as? [String: Any] else { return nil }
            object = nested
        }
        return object[key] as? String
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while normalized.count % 4 != 0 { normalized.append("=") }
        return Data(base64Encoded: normalized)
    }
}

/// Runs one authorization-code login: build the authorize URL, hand it to the
/// user's own browser, collect the code, exchange it for tokens.
///
/// The web view is never involved. The user logs in inside their real browser
/// with their real sessions, which is both better UX and the reason no
/// provider password ever touches this process.
public struct OAuthLoginFlow: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    private let profile: OAuthProviderProfile
    private let openURL: @Sendable (String) -> Void
    private let progress: @Sendable (LoginPhase) -> Void
    private let transport: Transport

    /// - Parameter transport: injected so the tests never reach the network.
    ///   The default goes through Core's shared client, which carries the
    ///   proxy and timeout policy every other request uses.
    public init(
        profile: OAuthProviderProfile,
        openURL: @escaping @Sendable (String) -> Void,
        progress: @escaping @Sendable (LoginPhase) -> Void,
        transport: @escaping Transport = { request in
            let response = try await ProviderHTTPClient.shared.response(for: request)
            return (response.data, response.statusCode)
        })
    {
        self.profile = profile
        self.openURL = openURL
        self.progress = progress
        self.transport = transport
    }

    /// - Parameter manualCode: asked for the pasted code when the profile uses
    ///   `.hostedCode`. Ignored for loopback profiles.
    public func run(
        manualCode: (@Sendable () async throws -> String)? = nil) async throws -> OAuthTokens
    {
        self.progress(.preparing)
        let codes = PKCECodes.generate()

        let code: String
        let redirectURI: String

        switch self.profile.redirect {
        case let .loopback(port, path):
            let server = try LoopbackCallbackServer(port: port, path: path)
            defer { server.close() }
            redirectURI = try Self.redirectURI(for: self.profile, loopbackPort: server.port)
            let url = Self.authorizeURL(profile: self.profile, codes: codes, redirectURI: redirectURI)
            self.progress(.waitingForBrowser(url: url))
            self.openURL(url)

            let request = try await server.waitForRequest(timeout: 300)
            if let error = Self.errorFromCallback(request.queryItems) { throw error }
            if let error = Self.validate(
                callbackState: request.queryItems["state"],
                expected: codes.state)
            {
                throw error
            }
            guard let received = request.queryItems["code"], !received.isEmpty else {
                throw LoginError.noAuthorizationCode
            }
            code = received

        case let .hostedCode(url: callbackURL):
            redirectURI = callbackURL
            let url = Self.authorizeURL(profile: self.profile, codes: codes, redirectURI: redirectURI)
            self.progress(.awaitingCode(url: url))
            self.openURL(url)
            guard let manualCode else { throw LoginError.cancelled }
            let pasted = try await manualCode()
            // Some providers show "<code>#<state>"; split and check the state.
            let parts = pasted.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#")
            guard let first = parts.first, !first.isEmpty else {
                throw LoginError.noAuthorizationCode
            }
            if parts.count > 1,
               let error = Self.validate(callbackState: String(parts[1]), expected: codes.state)
            {
                throw error
            }
            code = String(first)
        }

        self.progress(.exchanging)
        let request = try Self.tokenRequest(
            profile: self.profile,
            code: code,
            verifier: codes.verifier,
            redirectURI: redirectURI,
            state: codes.state)
        let (data, status) = try await self.transport(request)
        guard status == 200 else {
            throw LoginError.tokenRequestFailed(
                status: status,
                body: String(decoding: data, as: UTF8.self))
        }
        return try OAuthTokens.parse(data)
    }

    // MARK: - Pure parts, all unit-tested

    public static func redirectURI(
        for profile: OAuthProviderProfile,
        loopbackPort: UInt16?) throws -> String
    {
        switch profile.redirect {
        case let .loopback(_, path):
            guard let loopbackPort else { throw LoginError.cancelled }
            return "http://\(profile.loopbackHost):\(loopbackPort)\(path)"
        case let .hostedCode(url):
            return url
        }
    }

    public static func authorizeURL(
        profile: OAuthProviderProfile,
        codes: PKCECodes,
        redirectURI: String) -> String
    {
        var components = URLComponents(string: profile.authorizeURL)!
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: profile.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: profile.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: codes.state),
            URLQueryItem(name: "code_challenge", value: codes.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        // Sorted so the URL is reproducible and the tests can pin it.
        for key in profile.extraAuthorizeParameters.keys.sorted() {
            items.append(URLQueryItem(name: key, value: profile.extraAuthorizeParameters[key]))
        }
        // Escaped by hand for the same reason `formEncoded` exists: assigning
        // `queryItems` escapes for a URL query component, where `:` and `/` are
        // legal, so `redirect_uri` would go out bare as
        // `http://localhost:5555/callback`. The Claude CLI builds this URL with
        // `URLSearchParams`, which escapes them, and Claude's authorize
        // endpoint answers "Invalid request format" to the bare form.
        components.percentEncodedQuery = items
            .map { "\(Self.percentEscaped($0.name))=\(Self.percentEscaped($0.value ?? ""))" }
            .joined(separator: "&")
        return components.url?.absoluteString ?? profile.authorizeURL
    }

    /// Percent-encodes against RFC 3986's *unreserved* set, so the result is
    /// safe both as a query value and as a form field.
    ///
    /// A space becomes `%20` rather than `+`: `+` only means a space under
    /// form-urlencoded rules, while `%20` decodes to one under every reading.
    static func percentEscaped(_ value: String) -> String {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    public static func tokenRequest(
        profile: OAuthProviderProfile,
        code: String,
        verifier: String,
        redirectURI: String,
        state: String? = nil) throws -> URLRequest
    {
        guard let url = URL(string: profile.tokenURL) else {
            throw LoginError.malformedTokenResponse("bad token URL \(profile.tokenURL)")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var fields = [
            "grant_type": "authorization_code",
            "client_id": profile.clientID,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ]
        if profile.echoesStateInTokenRequest, let state {
            fields["state"] = state
        }

        switch profile.tokenEncoding {
        case .json:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        case .form:
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(Self.formEncoded(fields).utf8)
        }
        return request
    }

    /// Percent-encodes a form body against RFC 3986's *unreserved* set.
    ///
    /// `URLComponents.percentEncodedQuery` is not usable here: it encodes for a
    /// URL query component, where `:` `/` and `+` are all legal, so a
    /// `redirect_uri` would go out as `http://127.0.0.1:5555/callback` and a
    /// `+` would reach the server decoded as a space. A form body has to escape
    /// everything outside `A-Za-z0-9-._~`.
    static func formEncoded(_ fields: [String: String]) -> String {
        // Sorted so the body is reproducible and the tests can pin it.
        fields.keys.sorted()
            .map { "\(Self.percentEscaped($0))=\(Self.percentEscaped(fields[$0] ?? ""))" }
            .joined(separator: "&")
    }

    /// The provider signalled a failure in the redirect instead of a code.
    public static func errorFromCallback(_ queryItems: [String: String]) -> LoginError? {
        guard let error = queryItems["error"] else { return nil }
        if let description = queryItems["error_description"] {
            return .providerRejected("\(error): \(description)")
        }
        return .providerRejected(error)
    }

    /// A missing state is tolerated — some providers do not echo it — but a
    /// present and different one means this redirect belongs to another
    /// request and the code must not be spent.
    public static func validate(callbackState: String?, expected: String) -> LoginError? {
        guard let callbackState, !callbackState.isEmpty else { return nil }
        return callbackState == expected ? nil : .stateMismatch
    }
}
