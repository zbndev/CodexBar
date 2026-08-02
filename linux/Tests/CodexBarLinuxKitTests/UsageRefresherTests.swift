import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `a stored api key reaches the environment the strategies read`() {
    // Zai's strategy resolves its token from Z_AI_API_KEY only. Without the
    // config being folded into the environment, `isAvailable` is false and the
    // pipeline reports noAvailableStrategy — which is what the pane shows.
    var config = ProviderConfig(id: .zai)
    config.apiKey = "zai-key-value"
    let env = UsageRefresher.resolvedEnvironment(
        base: [:],
        provider: .zai,
        config: config)
    #expect(env[ZaiSettingsReader.apiTokenKey] == "zai-key-value")
    #expect(ZaiSettingsReader.apiToken(environment: env) == "zai-key-value")
}

@Test func `a stored kimi api key and base url reach the environment`() {
    var config = ProviderConfig(id: .kimi)
    config.apiKey = "kimi-key-value"
    let env = UsageRefresher.resolvedEnvironment(
        base: [:],
        provider: .kimi,
        config: config)
    #expect(KimiSettingsReader.apiKey(environment: env) == "kimi-key-value")
}

@Test func `the active token account is injected for the provider`() {
    // Copilot's accounts are what M4's device-code login writes; the fetch
    // path has to select the active one the same way macOS does.
    var config = ProviderConfig(id: .copilot)
    config.tokenAccounts = ProviderTokenAccountData(
        version: 1,
        accounts: [
            ProviderTokenAccount(id: UUID(), label: "first", token: "token-one", addedAt: 0, lastUsed: nil),
            ProviderTokenAccount(id: UUID(), label: "second", token: "token-two", addedAt: 0, lastUsed: nil),
        ],
        activeIndex: 1)
    #expect(UsageRefresher.activeTokenAccount(config)?.token == "token-two")
}

@Test func `an out-of-range active index does not trap`() {
    var config = ProviderConfig(id: .copilot)
    config.tokenAccounts = ProviderTokenAccountData(
        version: 1,
        accounts: [ProviderTokenAccount(id: UUID(), label: "only", token: "token-one", addedAt: 0, lastUsed: nil)],
        activeIndex: 7)
    #expect(UsageRefresher.activeTokenAccount(config)?.token == "token-one")
}

@Test func `no config leaves the base environment untouched`() {
    let env = UsageRefresher.resolvedEnvironment(
        base: ["EXISTING": "value"],
        provider: .zai,
        config: nil)
    #expect(env["EXISTING"] == "value")
    #expect(env[ZaiSettingsReader.apiTokenKey] == nil)
}
