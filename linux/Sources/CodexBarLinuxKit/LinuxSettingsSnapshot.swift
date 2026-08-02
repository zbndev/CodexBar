import CodexBarCore
import Foundation

/// Builds the `ProviderSettingsSnapshot` a fetch context carries, from the
/// config file the Linux GUI persists.
///
/// On macOS this snapshot is assembled by each provider implementation from
/// its `SettingsStore`; none of that layer exists here, and a context built
/// without it leaves every cookie strategy blind — `isAvailable` returns false
/// and the pipeline fails the provider with `noAvailableStrategy`.
///
/// Only cookie settings are contributed. That is deliberate: the embedded
/// login writes exactly `cookieSource` and `cookieHeader`, and every other
/// stored credential reaches strategies through
/// `UsageRefresher.resolvedEnvironment` instead.
public enum LinuxSettingsSnapshot {
    public static func make(config: CodexBarConfig?) -> ProviderSettingsSnapshot {
        var builder = ProviderSettingsSnapshotBuilder()
        let byID = Dictionary(
            (config?.providers ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })

        func cookie<Settings: ProviderCookieSettings>(_ provider: UsageProvider) -> Settings? {
            guard let stored = byID[provider] else { return nil }
            return Settings(
                cookieSource: stored.cookieSource ?? .auto,
                manualCookieHeader: stored.sanitizedCookieHeader)
        }

        builder.cursor = cookie(.cursor)
        builder.alibabaTokenPlan = cookie(.alibabatokenplan)
        builder.qwenCloud = cookie(.qwencloud)
        builder.factory = cookie(.factory)
        builder.manus = cookie(.manus)
        builder.kimi = cookie(.kimi)
        builder.longcat = cookie(.longcat)
        builder.augment = cookie(.augment)
        builder.amp = cookie(.amp)
        builder.t3chat = cookie(.t3chat)
        builder.zoommate = cookie(.zoommate)
        builder.commandcode = cookie(.commandcode)
        builder.ollama = cookie(.ollama)
        builder.perplexity = cookie(.perplexity)
        builder.mimo = cookie(.mimo)
        builder.abacus = cookie(.abacus)
        builder.mistral = cookie(.mistral)
        builder.qoder = cookie(.qoder)

        // These three carry the same pair under a different field name or
        // alongside extra state, so they cannot go through `cookie`.
        if let stored = byID[.opencode] {
            builder.opencode = ProviderSettingsSnapshot.OpenCodeProviderSettings(
                cookieSource: stored.cookieSource ?? .auto,
                manualCookieHeader: stored.sanitizedCookieHeader,
                workspaceID: stored.sanitizedWorkspaceID)
        }
        if let stored = byID[.opencodego] {
            builder.opencodego = ProviderSettingsSnapshot.OpenCodeProviderSettings(
                cookieSource: stored.cookieSource ?? .auto,
                manualCookieHeader: stored.sanitizedCookieHeader,
                workspaceID: stored.sanitizedWorkspaceID)
        }
        if let stored = byID[.stepfun] {
            // StepFun's manual credential is an Oasis-Token, and its username
            // and password have no config fields on Linux yet.
            builder.stepfun = ProviderSettingsSnapshot.StepFunProviderSettings(
                cookieSource: stored.cookieSource ?? .auto,
                manualToken: stored.sanitizedCookieHeader ?? "")
        }
        if let stored = byID[.devin] {
            // Devin's manual credential is an Authorization header value.
            builder.devin = ProviderSettingsSnapshot.DevinProviderSettings(
                cookieSource: stored.cookieSource ?? .auto,
                manualBearerToken: stored.sanitizedCookieHeader,
                organization: stored.sanitizedWorkspaceID)
        }

        return builder.build()
    }

    /// The manual cookie header the snapshot carries for `provider`, or nil
    /// when the provider contributes none. The inverse of `make`, and the one
    /// place that records which providers are covered.
    public static func cookieHeader(
        in snapshot: ProviderSettingsSnapshot,
        for provider: UsageProvider) -> String?
    {
        switch provider {
        case .cursor: snapshot.cursor?.manualCookieHeader
        case .alibabatokenplan: snapshot.alibabaTokenPlan?.manualCookieHeader
        case .qwencloud: snapshot.qwenCloud?.manualCookieHeader
        case .factory: snapshot.factory?.manualCookieHeader
        case .manus: snapshot.manus?.manualCookieHeader
        case .kimi: snapshot.kimi?.manualCookieHeader
        case .longcat: snapshot.longcat?.manualCookieHeader
        case .augment: snapshot.augment?.manualCookieHeader
        case .amp: snapshot.amp?.manualCookieHeader
        case .t3chat: snapshot.t3chat?.manualCookieHeader
        case .zoommate: snapshot.zoommate?.manualCookieHeader
        case .commandcode: snapshot.commandcode?.manualCookieHeader
        case .ollama: snapshot.ollama?.manualCookieHeader
        case .perplexity: snapshot.perplexity?.manualCookieHeader
        case .mimo: snapshot.mimo?.manualCookieHeader
        case .abacus: snapshot.abacus?.manualCookieHeader
        case .mistral: snapshot.mistral?.manualCookieHeader
        case .qoder: snapshot.qoder?.manualCookieHeader
        case .opencode: snapshot.opencode?.manualCookieHeader
        case .opencodego: snapshot.opencodego?.manualCookieHeader
        case .devin: snapshot.devin?.manualBearerToken
        case .stepfun: snapshot.stepfun?.manualToken
        default: nil
        }
    }
}
