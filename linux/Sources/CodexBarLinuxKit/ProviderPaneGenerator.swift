import CodexBarCore
import Foundation

/// Builds a provider's settings pane from Core data alone.
///
/// Nothing here switches on a provider id: membership tests against
/// `ProviderPaneTraits` are the only per-provider knowledge, which is what
/// lets an upstream-added provider render a working pane after a sync.
public enum ProviderPaneGenerator {
    public static func pane(
        for descriptor: ProviderDescriptor,
        config: ProviderConfig?) -> ProviderPanePayload
    {
        ProviderPanePayload(
            id: descriptor.id.rawValue,
            rows: self.rows(for: descriptor, config: config),
            tokenAccounts: config?.tokenAccounts,
            quotaWarnings: config?.quotaWarnings)
    }

    public static func rows(
        for descriptor: ProviderDescriptor,
        config: ProviderConfig?) -> [PaneRow]
    {
        let metadata = descriptor.metadata
        let modes = descriptor.fetchPlan.sourceModes
        // The per-provider words the descriptor cannot supply. nil means
        // "render exactly what M3 rendered".
        let copy = ProviderCopy.entry(for: descriptor.id)
        var rows: [PaneRow] = []

        rows.append(.header(
            displayName: metadata.displayName,
            subtitle: nil,
            iconSVG: ProviderIcons.svg(named: descriptor.branding.iconResourceName),
            accentColorHex: descriptor.branding.color.hexString))

        rows.append(.toggle(
            key: "enabled",
            title: "Enabled",
            value: config?.enabled ?? metadata.defaultEnabled))

        // Usage source picker: only when there is something to choose.
        let selectable = ProviderPaneTraits.sourceModeOrder.filter { modes.contains($0) }
        if selectable.count > 1 {
            rows.append(.picker(
                key: "source",
                title: "Usage source",
                options: selectable.map {
                    PaneOption(id: $0.rawValue, title: ProviderPaneTraits.sourceModeTitle($0))
                },
                selected: config?.source?.rawValue ?? ProviderSourceMode.auto.rawValue,
                visibleWhen: nil))
        }

        // One lookup, no per-provider switch: the catalog decides whether the
        // provider has an interactive login at all, and what to call it.
        if let title = LoginCatalog.buttonTitle(for: descriptor.id) {
            rows.append(.button(action: "login", title: title))
        }

        if ProviderPaneTraits.extrasToggleProviders.contains(descriptor.id) {
            rows.append(.toggle(
                key: "extrasEnabled",
                title: "Web dashboard extras",
                value: config?.extrasEnabled ?? false))
        }

        if modes.contains(.api) {
            rows.append(.field(
                key: "apiKey",
                title: "API key",
                value: config?.apiKey ?? "",
                secure: true,
                placeholder: copy?.placeholder,
                visibleWhen: nil))
        }
        if ProviderPaneTraits.secretKeyProviders.contains(descriptor.id) {
            rows.append(.field(
                key: "secretKey",
                title: "Secret key",
                value: config?.secretKey ?? "",
                secure: true,
                placeholder: nil,
                visibleWhen: nil))
        }

        if modes.contains(.web) {
            rows.append(.picker(
                key: "cookieSource",
                title: "Cookie source",
                options: ProviderCookieSource.allCases.map {
                    PaneOption(id: $0.rawValue, title: $0.displayName)
                },
                selected: config?.cookieSource?.rawValue ?? ProviderCookieSource.auto.rawValue,
                visibleWhen: nil))
            rows.append(.field(
                key: "cookieHeader",
                title: "Cookie header",
                value: config?.cookieHeader ?? "",
                secure: true,
                placeholder: copy?.placeholder,
                visibleWhen: RowCondition(key: "cookieSource", equals: "manual")))
            // Emitted once, here: the hint is about acquiring the session.
            if let hint = copy?.hint {
                rows.append(.hint(text: hint))
            }
        }

        if ProviderPaneTraits.regionProviders.contains(descriptor.id) {
            rows.append(.field(
                key: "region",
                title: "Region",
                value: config?.region ?? "",
                secure: false,
                placeholder: nil,
                visibleWhen: nil))
        }
        if ProviderPaneTraits.workspaceProviders.contains(descriptor.id) {
            rows.append(.field(
                key: "workspaceID",
                title: "Workspace / deployment",
                value: config?.workspaceID ?? "",
                secure: false,
                placeholder: nil,
                visibleWhen: nil))
        }
        if ProviderPaneTraits.enterpriseHostProviders.contains(descriptor.id) {
            rows.append(.field(
                key: "enterpriseHost",
                title: "Enterprise host",
                value: config?.enterpriseHost ?? "",
                secure: false,
                placeholder: nil,
                visibleWhen: nil))
        }
        if ProviderPaneTraits.awsProfileProviders.contains(descriptor.id) {
            rows.append(.picker(
                key: "awsAuthMode",
                title: "AWS authentication",
                options: BedrockAuthMode.allCases.map {
                    PaneOption(id: $0.rawValue, title: $0.rawValue.capitalized)
                },
                selected: config?.awsAuthMode ?? BedrockAuthMode.keys.rawValue,
                visibleWhen: nil))
            rows.append(.field(
                key: "awsProfile",
                title: "AWS profile",
                value: config?.awsProfile ?? "",
                secure: false,
                placeholder: nil,
                visibleWhen: nil))
        }

        if ProviderPaneTraits.profileScopeProviders.contains(descriptor.id) {
            rows.append(.field(
                key: "deepseekProfileID",
                title: "Profile ID",
                value: config?.deepseekProfileID ?? "",
                secure: false,
                placeholder: nil,
                visibleWhen: nil))
            rows.append(.field(
                key: "deepseekProfileScope",
                title: "Profile scope",
                value: config?.deepseekProfileScope ?? "",
                secure: false,
                placeholder: nil,
                visibleWhen: nil))
        }

        if TokenAccountSupportCatalog.support(for: descriptor.id) != nil {
            rows.append(.tokenAccounts(providerID: descriptor.id.rawValue))
        }

        if descriptor.id == .codex {
            rows.append(.managedCodexAccounts(providerID: descriptor.id.rawValue))
        }

        if ProviderPaneTraits.prioritizeExhaustedQuotaProviders.contains(descriptor.id) {
            rows.append(.toggle(
                key: "antigravityPrioritizeExhaustedQuotas",
                title: "Prioritize exhausted quotas",
                value: config?.antigravityPrioritizeExhaustedQuotas ?? false))
        }

        rows.append(.quotaWarnings(providerID: descriptor.id.rawValue))

        let links: [(String, String?)] = [
            ("Usage dashboard", metadata.dashboardURL),
            ("Subscription", metadata.subscriptionDashboardURL),
            ("Status page", metadata.statusPageURL),
            ("Changelog", metadata.changelogURL),
        ]
        let resolved = links.compactMap { title, url in url.map { (title, $0) } }
        // A helper link whose URL the metadata already resolved is dropped
        // rather than emitted twice (discovery 7).
        var emitted = Set(resolved.map(\.1))
        let helpers = (copy?.helperLinks ?? []).filter { emitted.insert($0.url).inserted }
        if !resolved.isEmpty || !helpers.isEmpty {
            rows.append(.section(title: "Links"))
            for (title, url) in resolved {
                rows.append(.link(title: title, url: url))
            }
            for link in helpers {
                rows.append(.link(title: link.title, url: link.url))
            }
        }

        return rows
    }
}
