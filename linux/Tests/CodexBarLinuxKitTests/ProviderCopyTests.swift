import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `every web-only provider has copy`() {
    for descriptor in ProviderDescriptorRegistry.webOnly {
        let entry = ProviderCopy.entry(for: descriptor.id)
        #expect(entry != nil, "no copy for \(descriptor.id.rawValue)")
        // A cookie-only provider must at least say what to paste.
        #expect(entry?.placeholder?.isEmpty == false || entry?.hint?.isEmpty == false)
    }
}

@Test func `the web-only set is the seventeen the milestone covers`() {
    // Guards the predicate itself: every descriptor also carries `.auto`, so
    // "web-only" means nothing beyond auto and web — not `sourceModes.count == 1`,
    // which matches nothing at all.
    #expect(ProviderDescriptorRegistry.webOnly.count == 17)
}

@Test func `every entry is well formed`() {
    for descriptor in ProviderDescriptorRegistry.all {
        guard let entry = ProviderCopy.entry(for: descriptor.id) else { continue }
        for link in entry.helperLinks {
            #expect(link.title.isEmpty == false)
            #expect(link.url.hasPrefix("https://"), "\(descriptor.id.rawValue): \(link.url)")
        }
        if let placeholder = entry.placeholder { #expect(placeholder.isEmpty == false) }
        if let hint = entry.hint { #expect(hint.isEmpty == false) }
    }
}

@Test func `the pinned entries carry the mined strings`() {
    // Verbatim from AbacusProviderImplementation.swift — the point of the
    // exercise is that the strings are mined, not rewritten.
    #expect(ProviderCopy.entry(for: .abacus)?.placeholder
        == "Cookie: \u{2026}\n\nor paste a cURL capture from the Abacus AI dashboard")
    #expect(ProviderCopy.entry(for: .perplexity)?.placeholder?.contains("Cookie") == true)
    #expect(ProviderCopy.entry(for: .codex) != nil)
    #expect(ProviderCopy.entry(for: .claude) != nil)
    #expect(ProviderCopy.entry(for: .copilot) != nil)
}

@Test func `a provider outside the seeded set has no entry`() {
    // Bedrock's settings are AWS-specific and self-explanatory. If the table
    // later grows to cover it, move this pin to another unseeded provider.
    #expect(ProviderCopy.entry(for: .bedrock) == nil)
}

@Test func `a field placeholder survives the wire`() throws {
    let row = PaneRow.field(
        key: "cookieHeader", title: "Cookie header", value: "",
        secure: true, placeholder: "Cookie: …",
        visibleWhen: RowCondition(key: "cookieSource", equals: "manual"))
    let data = try JSONEncoder().encode(row)
    #expect(try JSONDecoder().decode(PaneRow.self, from: data) == row)
}

@Test func `a field without a placeholder still decodes`() throws {
    // Payloads written before Task 9 have no placeholder key.
    let legacy = """
        {"kind":"field","key":"apiKey","title":"API key","value":"","secure":true}
        """
    let row = try JSONDecoder().decode(PaneRow.self, from: Data(legacy.utf8))
    guard case let .field(_, _, _, _, placeholder, _) = row else {
        Issue.record("expected a field row")
        return
    }
    #expect(placeholder == nil)
}

@Test func `a hint row round-trips`() throws {
    let row = PaneRow.hint(text: "Sign in, then paste the cookies your browser sends.")
    let data = try JSONEncoder().encode(row)
    #expect(try JSONDecoder().decode(PaneRow.self, from: data) == row)
}
