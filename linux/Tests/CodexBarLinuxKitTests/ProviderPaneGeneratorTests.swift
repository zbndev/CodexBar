import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private func rows(
    for provider: UsageProvider,
    config: ProviderConfig? = nil) -> [PaneRow]
{
    ProviderPaneGenerator.rows(
        for: ProviderDescriptorRegistry.descriptor(for: provider),
        config: config)
}

@Test func `every registered provider produces a non-empty pane`() {
    for descriptor in ProviderDescriptorRegistry.all {
        let rows = ProviderPaneGenerator.rows(for: descriptor, config: nil)
        #expect(!rows.isEmpty)
        #expect(rows.contains(.toggle(
            key: "enabled", title: "Enabled", value: descriptor.metadata.defaultEnabled)))
    }
}

@Test func `an api-capable provider gets an api key field`() {
    let pane = rows(for: .ollama)
    #expect(pane.contains(.field(
        key: "apiKey", title: "API key", value: "", secure: true, placeholder: nil, visibleWhen: nil)))
}

@Test func `a web-capable provider gets a cookie source picker and a manual-only header field`() {
    let pane = rows(for: .ollama)
    #expect(pane.contains(.picker(
        key: "cookieSource",
        title: "Cookie source",
        options: [
            PaneOption(id: "auto", title: "Auto"),
            PaneOption(id: "manual", title: "Manual"),
            PaneOption(id: "off", title: "Off"),
        ],
        selected: "auto",
        visibleWhen: nil)))
    #expect(pane.contains(.field(
        key: "cookieHeader",
        title: "Cookie header",
        value: "",
        secure: true,
        placeholder: nil,
        visibleWhen: RowCondition(key: "cookieSource", equals: "manual"))))
}

@Test func `a provider without web support gets no cookie rows`() {
    let pane = rows(for: .elevenlabs) // api-token only
    #expect(!pane.contains { row in
        if case .picker(let key, _, _, _, _) = row { return key == "cookieSource" }
        if case .field(let key, _, _, _, _, _) = row { return key == "cookieHeader" }
        return false
    })
}

@Test func `the source picker lists auto first and selects the configured mode`() {
    let config = ProviderConfig(id: .claude, source: .oauth)
    let pane = rows(for: .claude, config: config)
    guard case let .picker(_, _, options, selected, _) = pane.first(where: {
        if case .picker(let key, _, _, _, _) = $0 { return key == "source" }
        return false
    }) else {
        Issue.record("no source picker for claude")
        return
    }
    #expect(options.first?.id == "auto")
    #expect(selected == "oauth")
    #expect(options.contains(PaneOption(id: "api", title: "API key")))
}

@Test func `region-capable providers get a region field and others do not`() {
    #expect(rows(for: .minimax).contains(.field(
        key: "region", title: "Region", value: "", secure: false, placeholder: nil, visibleWhen: nil)))
    #expect(!rows(for: .claude).contains { row in
        if case .field(let key, _, _, _, _, _) = row { return key == "region" }
        return false
    })
}

@Test func `azure openai gets workspace and enterprise host fields`() {
    let pane = rows(for: .azureopenai)
    #expect(pane.contains(.field(
        key: "workspaceID", title: "Workspace / deployment", value: "", secure: false, placeholder: nil, visibleWhen: nil)))
    #expect(pane.contains(.field(
        key: "enterpriseHost", title: "Enterprise host", value: "", secure: false, placeholder: nil, visibleWhen: nil)))
}

@Test func `bedrock gets a secret key and aws profile fields`() {
    let pane = rows(for: .bedrock)
    #expect(pane.contains(.field(
        key: "secretKey", title: "Secret key", value: "", secure: true, placeholder: nil, visibleWhen: nil)))
    #expect(pane.contains(.field(
        key: "awsProfile", title: "AWS profile", value: "", secure: false, placeholder: nil, visibleWhen: nil)))
    #expect(pane.contains { row in
        if case .picker(let key, _, _, _, _) = row { return key == "awsAuthMode" }
        return false
    })
}

@Test func `doubao gets both access and secret key fields`() {
    let pane = rows(for: .doubao)
    #expect(pane.contains { row in
        if case .field(let key, _, _, _, _, _) = row { return key == "apiKey" }
        return false
    })
    #expect(pane.contains { row in
        if case .field(let key, _, _, _, _, _) = row { return key == "secretKey" }
        return false
    })
}

@Test func `token account capability comes from the Core support catalog`() {
    for descriptor in ProviderDescriptorRegistry.all {
        let hasRow = rows(for: descriptor.id).contains(
            .tokenAccounts(providerID: descriptor.id.rawValue))
        #expect(hasRow == (TokenAccountSupportCatalog.support(for: descriptor.id) != nil))
    }
}

@Test func `antigravity exposes exhausted quota priority`() {
    #expect(rows(for: .antigravity).contains(.toggle(
        key: "antigravityPrioritizeExhaustedQuotas",
        title: "Prioritize exhausted quotas",
        value: false)))
}

@Test func `deepseek profile fields are reachable`() {
    let pane = rows(for: .deepseek)
    for key in ["deepseekProfileID", "deepseekProfileScope"] {
        #expect(pane.contains { row in
            if case .field(let rowKey, _, _, _, _, _) = row { return rowKey == key }
            return false
        })
    }
}

@Test func `every non-deferred provider capability has a reachable row`() {
    for descriptor in ProviderDescriptorRegistry.all {
        let pane = ProviderPaneGenerator.rows(for: descriptor, config: nil)
        let keys = Set(pane.compactMap { row -> String? in
            switch row {
            case let .toggle(key, _, _): key
            case let .picker(key, _, _, _, _): key
            case let .field(key, _, _, _, _, _): key
            default: nil
            }
        })
        #expect(keys.contains("enabled"))
        if descriptor.fetchPlan.sourceModes.contains(.api) { #expect(keys.contains("apiKey")) }
        if descriptor.fetchPlan.sourceModes.contains(.web) {
            #expect(keys.contains("cookieSource"))
            #expect(keys.contains("cookieHeader"))
        }
        if ProviderPaneTraits.regionProviders.contains(descriptor.id) { #expect(keys.contains("region")) }
        if ProviderPaneTraits.workspaceProviders.contains(descriptor.id) { #expect(keys.contains("workspaceID")) }
        if ProviderPaneTraits.enterpriseHostProviders.contains(descriptor.id) {
            #expect(keys.contains("enterpriseHost"))
        }
        if ProviderPaneTraits.secretKeyProviders.contains(descriptor.id) { #expect(keys.contains("secretKey")) }
        if ProviderPaneTraits.awsProfileProviders.contains(descriptor.id) {
            #expect(keys.contains("awsProfile"))
            #expect(keys.contains("awsAuthMode"))
        }
        if ProviderPaneTraits.extrasToggleProviders.contains(descriptor.id) {
            #expect(keys.contains("extrasEnabled"))
        }
        if ProviderPaneTraits.prioritizeExhaustedQuotaProviders.contains(descriptor.id) {
            #expect(keys.contains("antigravityPrioritizeExhaustedQuotas"))
        }
        if ProviderPaneTraits.profileScopeProviders.contains(descriptor.id) {
            #expect(keys.contains("deepseekProfileID"))
            #expect(keys.contains("deepseekProfileScope"))
        }
        #expect(pane.contains(.quotaWarnings(providerID: descriptor.id.rawValue)))
        #expect(pane.contains(.tokenAccounts(providerID: descriptor.id.rawValue)) ==
            (TokenAccountSupportCatalog.support(for: descriptor.id) != nil))
    }
}

@Test func `dashboard and status links come from metadata`() {
    let pane = rows(for: .claude)
    let links = pane.compactMap { row -> (String, String)? in
        guard case let .link(title, url) = row else { return nil }
        return (title, url)
    }
    #expect(links.contains { $0.1 == ProviderDescriptorRegistry.descriptor(for: .claude).metadata.dashboardURL })
}

@Test func `every provider gets the quota warning editor row`() {
    for descriptor in ProviderDescriptorRegistry.all {
        let rows = ProviderPaneGenerator.rows(for: descriptor, config: nil)
        #expect(rows.contains(.quotaWarnings(providerID: descriptor.id.rawValue)))
    }
}

@Test func `a pane payload round-trips through JSON`() throws {
    let payload = ProviderPanePayload(
        id: "claude",
        rows: rows(for: .claude))
    let decoded = try JSONDecoder().decode(
        ProviderPanePayload.self,
        from: JSONEncoder().encode(payload))
    #expect(decoded == payload)
}

@Test func `a provider with a login route gets a sign-in button`() {
    #expect(rows(for: .claude).contains(.button(action: "login", title: "Sign in with Claude")))
}

@Test func `a provider without a login route gets no button`() {
    #expect(rows(for: .bedrock).allSatisfy { row in
        if case .button = row { return false }
        return true
    })
}
