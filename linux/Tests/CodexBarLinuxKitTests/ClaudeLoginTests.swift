import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("codexbar-claude-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let tokens = OAuthTokens(
    accessToken: "access-value",
    refreshToken: "refresh-value",
    idToken: nil,
    expiresIn: 3600,
    scope: "user:profile user:inference")

@Test func `the claude profile uses the client id and endpoints core already knows`() {
    let profile = ClaudeLogin.profile
    #expect(profile.providerID == "claude")
    #expect(profile.clientID == ClaudeOAuthCredentialsStore.defaultOAuthClientID)
    #expect(profile.tokenURL == "https://platform.claude.com/v1/oauth/token")
    #expect(profile.authorizeURL == "https://platform.claude.com/oauth/authorize")
    #expect(profile.scopes.contains("user:profile"))
    #expect(profile.scopes.contains("user:inference"))
    #expect(profile.scopes.contains("org:create_api_key"))
}

@Test func `the claude profile matches what the installed cli actually sends`() {
    // Measured from ~/.local/share/claude/versions/2.1.220. The CLI binds
    // 127.0.0.1 on an ephemeral port but puts "localhost" in the redirect_uri,
    // and its authorization_code exchange posts JSON — its form-urlencoded
    // request is the *refresh_token* grant, a different call.
    let profile = ClaudeLogin.profile
    #expect(profile.redirect == .loopback(port: 0, path: "/callback"))
    #expect(profile.loopbackHost == "localhost")
    #expect(profile.tokenEncoding == .json)
    #expect(profile.extraAuthorizeParameters["code"] == "true")
    #expect(profile.echoesStateInTokenRequest)
}

@Test func `the claude redirect uri is spelled the way the cli spells it`() throws {
    let uri = try OAuthLoginFlow.redirectURI(for: ClaudeLogin.profile, loopbackPort: 54545)
    #expect(uri == "http://localhost:54545/callback")
}

@Test func `the claude token request posts json carrying the state`() throws {
    let request = try OAuthLoginFlow.tokenRequest(
        profile: ClaudeLogin.profile,
        code: "the-code",
        verifier: "v-value",
        redirectURI: "http://localhost:54545/callback",
        state: "s-value")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let json = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: String]
    #expect(json["grant_type"] == "authorization_code")
    #expect(json["state"] == "s-value")
    #expect(json["redirect_uri"] == "http://localhost:54545/callback")
}

@Test func `merging into an absent file writes only the oauth block`() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let data = try ClaudeLogin.merge(tokens: tokens, into: nil, now: now)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let oauth = json["claudeAiOauth"] as! [String: Any]
    #expect(oauth["accessToken"] as? String == "access-value")
    #expect(oauth["refreshToken"] as? String == "refresh-value")
    // Core reads expiresAt as milliseconds since the epoch. Spelled as an
    // explicit Double: against a bare integer literal Swift picks an Int
    // comparison and the expectation fails on a value that is in fact correct.
    #expect(oauth["expiresAt"] as? Double == Double((1_000_000 + 3600) * 1000))
    #expect(oauth["scopes"] as? [String] == ["user:profile", "user:inference"])
}

@Test func `merging preserves sibling keys such as mcpOAuth`() throws {
    let existing = Data("""
    {"mcpOAuth":{"server":"keep-me"},"claudeAiOauth":{"accessToken":"old","subscriptionType":"max"}}
    """.utf8)
    let data = try ClaudeLogin.merge(tokens: tokens, into: existing, now: Date())
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect((json["mcpOAuth"] as? [String: Any])?["server"] as? String == "keep-me")
    let oauth = json["claudeAiOauth"] as! [String: Any]
    #expect(oauth["accessToken"] as? String == "access-value")
    // A field the token response does not carry keeps its previous value.
    #expect(oauth["subscriptionType"] as? String == "max")
}

@Test func `a token response without expires_in omits expiresAt rather than writing zero`() throws {
    let noExpiry = OAuthTokens(
        accessToken: "a", refreshToken: nil, idToken: nil, expiresIn: nil, scope: nil)
    let data = try ClaudeLogin.merge(tokens: noExpiry, into: nil, now: Date())
    let oauth = (try JSONSerialization.jsonObject(with: data) as! [String: Any])["claudeAiOauth"]
        as! [String: Any]
    #expect(oauth["expiresAt"] == nil)
}

@Test func `saving writes a 0600 file core can parse back`() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let environment = ["CLAUDE_CONFIG_DIR": directory.path]

    try ClaudeLogin.save(tokens: tokens, environment: environment, now: Date())

    let url = ClaudeLogin.credentialsURL(environment: environment)
    #expect(FileManager.default.fileExists(atPath: url.path))

    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.int16Value == 0o600)

    let parsed = try ClaudeOAuthCredentials.parse(data: try Data(contentsOf: url))
    #expect(parsed.accessToken == "access-value")
    #expect(parsed.refreshToken == "refresh-value")
}

@Test func `saving twice replaces the tokens and leaves one file behind`() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let environment = ["CLAUDE_CONFIG_DIR": directory.path]

    try ClaudeLogin.save(tokens: tokens, environment: environment, now: Date())
    let second = OAuthTokens(
        accessToken: "second-access", refreshToken: "second-refresh",
        idToken: nil, expiresIn: 60, scope: nil)
    try ClaudeLogin.save(tokens: second, environment: environment, now: Date())

    let url = ClaudeLogin.credentialsURL(environment: environment)
    let parsed = try ClaudeOAuthCredentials.parse(data: try Data(contentsOf: url))
    #expect(parsed.accessToken == "second-access")

    // No staging file may be left in the directory.
    let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(contents.filter { $0.contains("codexbar-staged") }.isEmpty)
}

@Test func `the private writer creates 0600 files and overwrites atomically`() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("secret.json")

    try PrivateFileWriter.write(Data("first".utf8), to: url)
    #expect(try String(contentsOf: url, encoding: .utf8) == "first")
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.int16Value == 0o600)

    try PrivateFileWriter.write(Data("second".utf8), to: url)
    #expect(try String(contentsOf: url, encoding: .utf8) == "second")
}

@Test func `the private writer creates missing intermediate directories`() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory
        .appendingPathComponent("nested", isDirectory: true)
        .appendingPathComponent("secret.json")
    try PrivateFileWriter.write(Data("x".utf8), to: url)
    #expect(FileManager.default.fileExists(atPath: url.path))
}
