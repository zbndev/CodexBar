import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `every web provider has a login entry`() {
    for descriptor in ProviderDescriptorRegistry.all
        where descriptor.fetchPlan.sourceModes.contains(.web)
    {
        let entry = ProviderLoginCatalog.entry(for: descriptor.id)
        #expect(entry != nil, "no cookie login entry for \(descriptor.id.rawValue)")
        #expect(entry?.loginURL.hasPrefix("https://") == true)
        #expect(entry?.cookieURLs.isEmpty == false)
    }
}

@Test func `a provider without web support has no entry`() {
    // Bedrock is API/keys only.
    #expect(ProviderLoginCatalog.entry(for: .bedrock) == nil)
}

@Test func `the default entry comes from the dashboard url`() {
    let entry = ProviderLoginCatalog.entry(for: .perplexity)
    #expect(entry?.loginURL == "https://www.perplexity.ai/account/usage")
    // Cookies are collected from the origin, not the deep-linked page.
    #expect(entry?.cookieURLs.contains("https://www.perplexity.ai/") == true)
}

@Test func `opencode overrides the catalog with its second host`() {
    let entry = ProviderLoginCatalog.entry(for: .opencode)
    #expect(entry?.cookieURLs.contains("https://opencode.ai/") == true)
    #expect(entry?.cookieURLs.contains("https://app.opencode.ai/") == true)
    #expect(entry?.requiredCookieNames.contains("auth") == true)
}

@Test func `validation accepts a header carrying any required cookie`() {
    let required: Set<String> = ["auth", "__Host-auth"]
    #expect(ProviderLoginCatalog.validate(header: "__Host-auth=v; other=1", against: required))
    #expect(ProviderLoginCatalog.validate(header: "auth=v", against: required))
    #expect(!ProviderLoginCatalog.validate(header: "other=1", against: required))
    #expect(!ProviderLoginCatalog.validate(header: "", against: required))
}

@Test func `validation with no required names accepts any non-empty header`() {
    #expect(ProviderLoginCatalog.validate(header: "anything=1", against: []))
    #expect(!ProviderLoginCatalog.validate(header: "   ", against: []))
}

@Test func `the origin helper strips paths and keeps ports`() {
    #expect(ProviderLoginCatalog.origin(of: "https://www.perplexity.ai/account/usage")
        == "https://www.perplexity.ai/")
    #expect(ProviderLoginCatalog.origin(of: "https://opencode.ai") == "https://opencode.ai/")
    #expect(ProviderLoginCatalog.origin(of: "https://x.example:8443/a/b")
        == "https://x.example:8443/")
    #expect(ProviderLoginCatalog.origin(of: "not a url") == nil)
}

@Test func `the app-scheme policy blocks everything but codexbar`() {
    #expect(WebView.isNavigationAllowed(uri: "codexbar://ui/index.html", policy: .appSchemeOnly))
    #expect(!WebView.isNavigationAllowed(uri: "https://example.com/", policy: .appSchemeOnly))
    #expect(!WebView.isNavigationAllowed(uri: "file:///etc/passwd", policy: .appSchemeOnly))
}

@Test func `the login policy allows https and nothing else`() {
    // Provider logins bounce through identity providers, so any https host
    // must be reachable.
    #expect(WebView.isNavigationAllowed(uri: "https://accounts.google.com/o/oauth2/v2/auth", policy: .anyHTTPS))
    #expect(WebView.isNavigationAllowed(uri: "https://opencode.ai/", policy: .anyHTTPS))
    #expect(!WebView.isNavigationAllowed(uri: "http://opencode.ai/", policy: .anyHTTPS))
    #expect(!WebView.isNavigationAllowed(uri: "file:///etc/passwd", policy: .anyHTTPS))
    #expect(!WebView.isNavigationAllowed(uri: "codexbar://ui/index.html", policy: .anyHTTPS))
}

@Test func `merging cookie pairs keeps the last value for a repeated name`() {
    let merged = CookieHarvester.mergePairs([
        [("a", "1"), ("b", "2")],
        [("b", "3"), ("c", "4")],
    ])
    #expect(merged == "a=1; b=3; c=4")
}

@Test func `merging an empty set yields an empty header`() {
    #expect(CookieHarvester.mergePairs([]) == "")
    #expect(CookieHarvester.mergePairs([[]]) == "")
}

@Test func `a harvested header parses back through core's normalizer`() {
    let header = CookieHarvester.mergePairs([[("session", "abc"), ("csrf", "def")]])
    let pairs = CookieHeaderNormalizer.pairs(from: header)
    #expect(pairs.count == 2)
    #expect(pairs.first(where: { $0.name == "session" })?.value == "abc")
}
