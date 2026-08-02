import Foundation
import Testing

@testable import CodexBarLinuxKit

private let formProfile = OAuthProviderProfile(
    providerID: "example",
    clientID: "client-123",
    authorizeURL: "https://auth.example.com/oauth/authorize",
    tokenURL: "https://auth.example.com/oauth/token",
    scopes: ["read", "write"],
    redirect: .loopback(port: 0, path: "/callback"),
    tokenEncoding: .form,
    extraAuthorizeParameters: ["prompt": "login"])

private let jsonProfile = OAuthProviderProfile(
    providerID: "example-json",
    clientID: "client-123",
    authorizeURL: "https://auth.example.com/oauth/authorize",
    tokenURL: "https://auth.example.com/oauth/token",
    scopes: ["openid"],
    redirect: .hostedCode(url: "https://auth.example.com/oauth/code/callback"),
    tokenEncoding: .json,
    extraAuthorizeParameters: [:])

private let codes = PKCECodes(verifier: "v-value", challenge: "c-value", state: "s-value")

@Test func `the authorize url carries pkce, state, scopes and extras`() {
    let url = OAuthLoginFlow.authorizeURL(
        profile: formProfile,
        codes: codes,
        redirectURI: "http://127.0.0.1:5555/callback")
    let components = URLComponents(string: url)!
    let items = Dictionary(
        uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

    #expect(components.host == "auth.example.com")
    #expect(components.path == "/oauth/authorize")
    #expect(items["response_type"] == "code")
    #expect(items["client_id"] == "client-123")
    #expect(items["redirect_uri"] == "http://127.0.0.1:5555/callback")
    #expect(items["scope"] == "read write")
    #expect(items["state"] == "s-value")
    #expect(items["code_challenge"] == "c-value")
    #expect(items["code_challenge_method"] == "S256")
    #expect(items["prompt"] == "login")
    // The verifier is the secret half — it must never be in the browser URL.
    #expect(!url.contains("v-value"))
}

@Test func `query values are percent encoded`() {
    let url = OAuthLoginFlow.authorizeURL(
        profile: formProfile,
        codes: codes,
        redirectURI: "http://127.0.0.1:5555/callback")
    #expect(url.contains("scope=read%20write") || url.contains("scope=read+write"))
}

@Test func `a form token request posts urlencoded fields`() throws {
    let request = try OAuthLoginFlow.tokenRequest(
        profile: formProfile,
        code: "the-code",
        verifier: "v-value",
        redirectURI: "http://127.0.0.1:5555/callback")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    #expect(body.contains("grant_type=authorization_code"))
    #expect(body.contains("code=the-code"))
    #expect(body.contains("code_verifier=v-value"))
    #expect(body.contains("client_id=client-123"))
    #expect(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A5555%2Fcallback"))
}

@Test func `a json token request posts a json object`() throws {
    let request = try OAuthLoginFlow.tokenRequest(
        profile: jsonProfile,
        code: "the-code",
        verifier: "v-value",
        redirectURI: "https://auth.example.com/oauth/code/callback")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let json = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: String]
    #expect(json["grant_type"] == "authorization_code")
    #expect(json["code"] == "the-code")
    #expect(json["code_verifier"] == "v-value")
    #expect(json["client_id"] == "client-123")
}

@Test func `token responses parse snake case fields`() throws {
    let data = Data("""
    {"access_token":"at","refresh_token":"rt","id_token":"it","expires_in":3600,"scope":"read write"}
    """.utf8)
    let tokens = try OAuthTokens.parse(data)
    #expect(tokens.accessToken == "at")
    #expect(tokens.refreshToken == "rt")
    #expect(tokens.idToken == "it")
    #expect(tokens.expiresIn == 3600)
    #expect(tokens.scope == "read write")
}

@Test func `a token response without an access token is rejected`() {
    let data = Data(#"{"refresh_token":"rt"}"#.utf8)
    #expect(throws: (any Error).self) { try OAuthTokens.parse(data) }
}

@Test func `a callback carrying an error is reported with the provider message`() {
    let error = OAuthLoginFlow.errorFromCallback(
        ["error": "access_denied", "error_description": "User said no"])
    #expect(error == .providerRejected("access_denied: User said no"))
    #expect(OAuthLoginFlow.errorFromCallback(["code": "ok"]) == nil)
}

@Test func `a mismatched state is rejected before the code is used`() {
    #expect(OAuthLoginFlow.validate(callbackState: "wrong", expected: "s-value") == .stateMismatch)
    #expect(OAuthLoginFlow.validate(callbackState: "s-value", expected: "s-value") == nil)
    // A provider that echoes no state at all is not an attack, only sloppy.
    #expect(OAuthLoginFlow.validate(callbackState: nil, expected: "s-value") == nil)
}

@Test func `jwt claims are read from the id token payload`() {
    // {"alg":"none"}.{"sub":"u1","https://api.openai.com/auth":{"chatgpt_account_id":"acct-9"}}
    let header = "eyJhbGciOiJub25lIn0"
    let payload = "eyJzdWIiOiJ1MSIsImh0dHBzOi8vYXBpLm9wZW5haS5jb20vYXV0aCI6eyJjaGF0Z3B0X2FjY291bnRfaWQiOiJhY2N0LTkifX0"
    let token = "\(header).\(payload).sig"
    #expect(JWTClaims.string("sub", path: [], inIDToken: token) == "u1")
    #expect(JWTClaims.string(
        "chatgpt_account_id",
        path: ["https://api.openai.com/auth"],
        inIDToken: token) == "acct-9")
    #expect(JWTClaims.string("missing", path: [], inIDToken: token) == nil)
    #expect(JWTClaims.string("sub", path: [], inIDToken: "not-a-jwt") == nil)
}

@Test func `a hosted-code profile builds its redirect uri from the profile`() throws {
    #expect(try OAuthLoginFlow.redirectURI(for: jsonProfile, loopbackPort: nil)
        == "https://auth.example.com/oauth/code/callback")
}

@Test func `a loopback profile builds its redirect uri from the bound port`() throws {
    #expect(try OAuthLoginFlow.redirectURI(for: formProfile, loopbackPort: 5555)
        == "http://127.0.0.1:5555/callback")
}
