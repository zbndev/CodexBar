import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `claude and codex route to oauth with their profiles`() {
    guard case let .oauth(profile, title, _) = LoginCatalog.route(for: .claude) else {
        Issue.record("claude should route to oauth")
        return
    }
    #expect(profile.clientID == ClaudeOAuthCredentialsStore.defaultOAuthClientID)
    #expect(title == "Sign in with Claude")

    guard case let .oauth(codexProfile, codexTitle, _) = LoginCatalog.route(for: .codex) else {
        Issue.record("codex should route to oauth")
        return
    }
    #expect(codexProfile.authorizeURL == "https://auth.openai.com/oauth/authorize")
    #expect(codexTitle == "Sign in with OpenAI")
}

@Test func `copilot routes to the device flow`() {
    guard case .deviceFlow = LoginCatalog.route(for: .copilot) else {
        Issue.record("copilot should route to the device flow")
        return
    }
}

@Test func `Google providers route to official external credential tools`() {
    for provider: UsageProvider in [.gemini, .antigravity, .vertexai] {
        guard case let .externalCredential(entry) = LoginCatalog.route(for: provider) else {
            Issue.record("\(provider.rawValue) should route to its official credential tool")
            return
        }
        #expect(entry.provider == provider)
    }
}

@Test func `web providers route to the embedded cookie login`() {
    guard case let .embeddedCookie(entry) = LoginCatalog.route(for: .perplexity) else {
        Issue.record("perplexity should route to the cookie login")
        return
    }
    #expect(entry.loginURL == "https://www.perplexity.ai/account/usage")
}

@Test func `every web-only provider has a login route`() {
    for descriptor in ProviderDescriptorRegistry.webOnly {
        if case .none = LoginCatalog.route(for: descriptor.id) {
            Issue.record("\(descriptor.id.rawValue) is web-only but has no login route")
        }
    }
}

@Test func `an api-only provider has no login route`() {
    // Bedrock is keys/AWS-profile only.
    if case .some = LoginCatalog.route(for: .bedrock) {
        Issue.record("bedrock has no interactive login")
    }
}

@Test func `the button title exists exactly when a route does`() {
    for descriptor in ProviderDescriptorRegistry.all {
        let hasRoute = switch LoginCatalog.route(for: descriptor.id) {
        case .some: true
        case .none: false
        }
        #expect((LoginCatalog.buttonTitle(for: descriptor.id) != nil) == hasRoute)
    }
    #expect(LoginCatalog.buttonTitle(for: .copilot) == "Sign in with GitHub")
}

@Test func `every phase maps to its wire name`() {
    #expect(LoginPhasePayload(.preparing).phase == "preparing")
    #expect(LoginPhasePayload(.waitingForBrowser(url: "https://x")).url == "https://x")
    #expect(LoginPhasePayload(.awaitingCode(url: "https://y")).phase == "awaitingCode")
    #expect(
        LoginPhasePayload(.showingDeviceCode(code: "ABCD-1234", url: "https://u")).code
            == "ABCD-1234")
    #expect(LoginPhasePayload(.exchanging).phase == "exchanging")
    #expect(LoginPhasePayload(.saving).phase == "saving")
    #expect(LoginPhasePayload(.finished).phase == "finished")
    #expect(LoginPhasePayload(.failed(message: "boom")).message == "boom")
    #expect(LoginPhasePayload(.waitingForExternalTool(
        command: "gcloud auth application-default login",
        helpURL: "https://docs.cloud.google.com/docs/authentication/application-default-credentials")).helpURL
        == "https://docs.cloud.google.com/docs/authentication/application-default-credentials")
}

@Test func `the payload round-trips and has nowhere to hide a credential`() throws {
    let payload = LoginPhasePayload(
        .showingDeviceCode(code: "ABCD-1234", url: "https://github.com/login/device"))
    let data = try JSONEncoder().encode(payload)
    #expect(try JSONDecoder().decode(LoginPhasePayload.self, from: data) == payload)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    // The wire keys are exactly these. A token or cookie header has no field
    // to travel in — that is the secrets constraint made structural.
    #expect(Set(object.keys).isSubset(of: ["phase", "url", "code", "message", "command", "helpURL"]))
}
