import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private func config(_ provider: UsageProvider, header: String?) -> CodexBarConfig {
    var providerConfig = ProviderConfig(id: provider.instanceID)
    providerConfig.cookieSource = .manual
    providerConfig.cookieHeader = header
    var config = CodexBarConfig.makeDefault()
    config.providers.removeAll { $0.id == provider.instanceID }
    config.providers.append(providerConfig)
    return config
}

@Test func `a saved cookie header reaches the provider's settings snapshot`() {
    // What the embedded cookie login writes must be what the web strategy
    // reads. Kimi's strategy resolves it through context.settings?.kimi.
    let snapshot = LinuxSettingsSnapshot.make(config: config(.kimi, header: "kimi-auth=abc"))
    #expect(snapshot.kimi?.cookieSource == .manual)
    #expect(snapshot.kimi?.manualCookieHeader == "kimi-auth=abc")
}

@Test func `the snapshot satisfies the strategy's own availability check`() {
    // The end-to-end assertion: with the snapshot in the context, Kimi's web
    // strategy resolves an override instead of reporting itself unavailable.
    let snapshot = LinuxSettingsSnapshot.make(config: config(.kimi, header: "kimi-auth=abc"))
    let context = UsageRefresher.makeContext(
        descriptor: ProviderDescriptorRegistry.descriptor(for: .kimi),
        sourceMode: .web,
        environment: [:],
        settings: snapshot)
    #expect(KimiCookieHeader.resolveCookieOverride(context: context)?.token == "abc")
}

@Test func `every web-only provider can see its saved cookie header`() {
    // A provider added upstream with a web source but no route from config to
    // a strategy would silently keep failing with noAvailableStrategy. Both
    // routes count: most read the snapshot, a few (Sakana, LongCat, DeepSeek)
    // have Core project the header onto an environment variable instead.
    for descriptor in ProviderDescriptorRegistry.webOnly {
        let stored = config(descriptor.id, header: "session=value")
        let snapshot = LinuxSettingsSnapshot.make(config: stored)
        let viaSnapshot =
            LinuxSettingsSnapshot.cookieHeader(in: snapshot, for: descriptor.id) == "session=value"
        let environment = UsageRefresher.resolvedEnvironment(
            base: [:],
            provider: descriptor.id,
            config: stored.providerConfig(for: descriptor.id.instanceID))
        let viaEnvironment = environment.values.contains("session=value")
        #expect(
            viaSnapshot || viaEnvironment,
            "\(descriptor.id.rawValue) cannot see its saved cookie header")
    }
}

@Test func `a provider with no stored config contributes nothing`() {
    let snapshot = LinuxSettingsSnapshot.make(config: CodexBarConfig.makeDefault())
    #expect(snapshot.kimi?.manualCookieHeader == nil)
}
