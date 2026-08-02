import CodexBarCore
import Foundation

/// Where to send the user to sign in, and where to read the resulting cookies.
public struct CookieLoginEntry: Equatable, Sendable {
    /// The page the login window opens.
    public let loginURL: String
    /// URIs cookies are collected from. Querying by URI already picks up
    /// parent-domain cookies, so more than one entry is needed only when the
    /// session genuinely spans hosts.
    public let cookieURLs: [String]
    /// Any one of these must be present for the harvest to count. Empty means
    /// "any non-empty header".
    public let requiredCookieNames: Set<String>

    public init(loginURL: String, cookieURLs: [String], requiredCookieNames: Set<String> = []) {
        self.loginURL = loginURL
        self.cookieURLs = cookieURLs
        self.requiredCookieNames = requiredCookieNames
    }
}

/// Per-provider cookie-login data.
///
/// The default is derived from Core: `metadata.dashboardURL` is a real,
/// sign-in-able page for every web provider, so a provider added upstream gets
/// a working login without an entry here. The table below holds only the cases
/// where that default is wrong — a session spanning two hosts, or a cookie
/// name worth checking for.
///
/// Values come from Core's own `*CookieImporter` types, which carry the
/// authoritative domain lists but are all `#if os(macOS)` and therefore
/// unreachable at runtime on Linux.
public enum ProviderLoginCatalog {
    private struct Override {
        let loginURL: String?
        let extraCookieURLs: [String]
        let requiredCookieNames: Set<String>

        init(
            loginURL: String? = nil,
            extraCookieURLs: [String] = [],
            requiredCookieNames: Set<String> = [])
        {
            self.loginURL = loginURL
            self.extraCookieURLs = extraCookieURLs
            self.requiredCookieNames = requiredCookieNames
        }
    }

    private static let overrides: [UsageProvider: Override] = [
        // OpenCodeCookieImporter.swift: cookies span both hosts, and the
        // importer refuses a session without an auth cookie.
        .opencode: Override(
            extraCookieURLs: ["https://app.opencode.ai/"],
            requiredCookieNames: ["auth", "__Host-auth"]),
        .opencodego: Override(
            extraCookieURLs: ["https://app.opencode.ai/"],
            requiredCookieNames: ["auth", "__Host-auth"]),
        // MistralCookieImporter.swift: the console and the admin dashboard are
        // separate hosts sharing one session.
        .mistral: Override(
            extraCookieURLs: ["https://console.mistral.ai/", "https://auth.mistral.ai/"]),
        // AbacusCookieImporter.swift
        .abacus: Override(extraCookieURLs: ["https://abacus.ai/"]),
        // MiMoCookieImporter.swift
        .mimo: Override(extraCookieURLs: ["https://xiaomimimo.com/"]),
        // MiniMaxCookieImporter.swift
        .minimax: Override(extraCookieURLs: ["https://openplatform.minimax.io/", "https://minimax.io/"]),
        // QwenCloudCookieImporter.swift
        .qwencloud: Override(
            extraCookieURLs: ["https://home.qwencloud.com/", "https://account.qwencloud.com/"]),
        // ZoomMateCookieImporter.swift
        .zoommate: Override(extraCookieURLs: ["https://ai.zoom.us/", "https://zoom.us/"]),
        // AlibabaCodingPlanCookieImporter.swift: the console host differs from
        // the API host the descriptor points at.
        .alibaba: Override(extraCookieURLs: ["https://bailian-cs.console.aliyun.com/"]),
        .alibabatokenplan: Override(extraCookieURLs: ["https://bailian-cs.console.aliyun.com/"]),
        // LongCatCookieImporter.swift
        .longcat: Override(extraCookieURLs: ["https://www.longcat.chat/"]),
        // ManusCookieImporter.swift
        .manus: Override(extraCookieURLs: ["https://www.manus.im/"]),
        // CommandCodeCookieImporter.swift
        .commandcode: Override(extraCookieURLs: ["https://www.commandcode.ai/"]),
        // KimiCookieImporter.swift
        .kimi: Override(extraCookieURLs: ["https://kimi.com/"]),
        // OpenAIDashboardBrowserCookieImporter.swift: Codex's web extras read
        // the ChatGPT session, which is not where the Codex dashboard points.
        .codex: Override(
            loginURL: "https://chatgpt.com/",
            extraCookieURLs: ["https://openai.com/"]),
    ]

    public static func entry(for provider: UsageProvider) -> CookieLoginEntry? {
        // `descriptor(for:)` is non-optional — it synthesises a fallback for an
        // unknown id — so the web check is what decides whether an entry exists.
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        guard descriptor.fetchPlan.sourceModes.contains(.web) else { return nil }

        let override = self.overrides[provider]
        guard let loginURL = override?.loginURL ?? descriptor.metadata.dashboardURL,
              let origin = self.origin(of: loginURL)
        else {
            return nil
        }
        var cookieURLs = [origin]
        for extra in override?.extraCookieURLs ?? [] where !cookieURLs.contains(extra) {
            cookieURLs.append(extra)
        }
        return CookieLoginEntry(
            loginURL: loginURL,
            cookieURLs: cookieURLs,
            requiredCookieNames: override?.requiredCookieNames ?? [])
    }

    /// `https://host[:port]/` for a URL, which is what the cookie manager wants.
    public static func origin(of urlString: String) -> String? {
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme,
              let host = components.host,
              !host.isEmpty
        else {
            return nil
        }
        let port = components.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)/"
    }

    /// True when the harvested header is worth saving.
    public static func validate(header: String, against required: Set<String>) -> Bool {
        let pairs = CookieHeaderNormalizer.pairs(from: header)
        guard !pairs.isEmpty else { return false }
        guard !required.isEmpty else { return true }
        return pairs.contains { required.contains($0.name) }
    }
}
