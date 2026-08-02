import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private func temporaryHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("codexbar-codex-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// header {"alg":"none"} . payload {"https://api.openai.com/auth":{"chatgpt_account_id":"acct-42"}}
private let idToken = "eyJhbGciOiJub25lIn0."
    + "eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdC00MiJ9fQ"
    + ".sig"

@Test func `the codex profile posts json and asks for offline access`() {
    let profile = CodexLogin.profile
    #expect(profile.providerID == "codex")
    #expect(profile.clientID == "app_EMoamEEZ73f0CkXaXp7hrann")
    #expect(profile.tokenURL == "https://auth.openai.com/oauth/token")
    #expect(profile.authorizeURL == "https://auth.openai.com/oauth/authorize")
    #expect(profile.tokenEncoding == .json)
    // Without offline_access there is no refresh_token, and Core's 8-day
    // refresh would have nothing to use.
    #expect(profile.scopes.contains("offline_access"))
    #expect(profile.scopes.contains("openid"))
}

@Test func `the codex profile uses a fixed loopback port, not an ephemeral one`() {
    guard case let .loopback(port, path) = CodexLogin.profile.redirect else {
        Issue.record("Codex must redirect to a loopback path")
        return
    }
    // The authorization server matches redirect_uri exactly, so port 0 would
    // produce a different URI on every attempt and be rejected.
    #expect(port != 0)
    #expect(path == "/auth/callback")
}

@Test func `the codex redirect uri reproduces what codex login prints`() throws {
    // Measured 2026-08-02 by running `codex login` and reading its own URL:
    //   redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback
    // and `ss` showing codex listening on 127.0.0.1:1455.
    #expect(CodexLogin.profile.loopbackHost == "localhost")
    guard case let .loopback(port, _) = CodexLogin.profile.redirect else {
        Issue.record("Codex must redirect to a loopback path")
        return
    }
    let uri = try OAuthLoginFlow.redirectURI(for: CodexLogin.profile, loopbackPort: port)
    #expect(uri == "http://localhost:1455/auth/callback")
}

@Test func `the codex authorize url asks for the organization claim`() {
    // id_token_add_organizations=true is what puts the
    // https://api.openai.com/auth block — and so chatgpt_account_id — into the
    // id token that `accountID(from:)` reads.
    #expect(CodexLogin.profile.extraAuthorizeParameters["id_token_add_organizations"] == "true")

    let url = OAuthLoginFlow.authorizeURL(
        profile: CodexLogin.profile,
        codes: PKCECodes(verifier: "v", challenge: "c", state: "s"),
        redirectURI: "http://localhost:1455/auth/callback")
    let items = Dictionary(
        uniqueKeysWithValues: (URLComponents(string: url)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
    #expect(items["id_token_add_organizations"] == "true")
    #expect(items["code_challenge_method"] == "S256")
    #expect(items["redirect_uri"] == "http://localhost:1455/auth/callback")
}

@Test func `the account id is recovered from the id token claim`() {
    let tokens = OAuthTokens(
        accessToken: "a", refreshToken: "r", idToken: idToken, expiresIn: nil, scope: nil)
    #expect(CodexLogin.accountID(from: tokens) == "acct-42")
}

@Test func `an explicit account_id field wins over the id token claim`() {
    let tokens = OAuthTokens(
        accessToken: "a", refreshToken: "r", idToken: idToken,
        expiresIn: nil, scope: nil, accountID: "explicit")
    #expect(CodexLogin.accountID(from: tokens) == "explicit")
}

@Test func `a token set with no id token yields no account id`() {
    let tokens = OAuthTokens(
        accessToken: "a", refreshToken: "r", idToken: nil, expiresIn: nil, scope: nil)
    #expect(CodexLogin.accountID(from: tokens) == nil)
}

@Test func `saving writes an auth file core can load back`() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let environment = ["CODEX_HOME": home.path]

    let tokens = OAuthTokens(
        accessToken: "access-value", refreshToken: "refresh-value",
        idToken: idToken, expiresIn: 3600, scope: "openid")
    try CodexLogin.save(tokens: tokens, environment: environment)

    let loaded = try CodexOAuthCredentialsStore.loadOAuthTokens(env: environment)
    #expect(loaded.accessToken == "access-value")
    #expect(loaded.refreshToken == "refresh-value")
    #expect(loaded.accountId == "acct-42")
    #expect(loaded.needsRefresh == false)

    let url = home.appendingPathComponent("auth.json")
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.int16Value == 0o600)
}

@Test func `saving preserves an unrelated key already in auth.json`() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let environment = ["CODEX_HOME": home.path]
    let url = home.appendingPathComponent("auth.json")
    try Data(#"{"OPENAI_API_KEY":"sk-keep-me"}"#.utf8).write(to: url)

    let tokens = OAuthTokens(
        accessToken: "access-value", refreshToken: "refresh-value",
        idToken: nil, expiresIn: nil, scope: nil)
    try CodexLogin.save(tokens: tokens, environment: environment)

    let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as! [String: Any]
    #expect(json["OPENAI_API_KEY"] as? String == "sk-keep-me")
    #expect((json["tokens"] as? [String: Any])?["access_token"] as? String == "access-value")
}
