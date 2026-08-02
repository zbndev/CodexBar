import CodexBarCore
import Foundation

// The Core token-account types are Codable/Sendable but not Equatable, while
// every bridge envelope is. Compare each stored field so the round-trip tests
// stay meaningful rather than trivially true.
extension ProviderTokenAccount: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id &&
            lhs.label == rhs.label &&
            lhs.token == rhs.token &&
            lhs.addedAt == rhs.addedAt &&
            lhs.lastUsed == rhs.lastUsed &&
            lhs.externalIdentifier == rhs.externalIdentifier &&
            lhs.usageScope == rhs.usageScope &&
            lhs.organizationID == rhs.organizationID &&
            lhs.workspaceID == rhs.workspaceID
    }
}

extension ProviderTokenAccountData: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.version == rhs.version &&
            lhs.accounts == rhs.accounts &&
            lhs.activeIndex == rhs.activeIndex
    }
}

/// One option in a `.picker` row.
public struct PaneOption: Codable, Equatable, Sendable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// A visibility rule: the row renders only when the current value of `key`
/// equals `equals`. Reproduces the macOS panes' thin conditions (e.g. the
/// cookie header shows only for `cookieSource == manual`) as data, so the
/// renderer needs no per-provider logic.
public struct RowCondition: Codable, Equatable, Sendable {
    public var key: String
    public var equals: String

    public init(key: String, equals: String) {
        self.key = key
        self.equals = equals
    }
}

/// Every row a settings pane can contain.
///
/// Both provider panes and the nine general panes are lists of these. The
/// two editor rows (`tokenAccounts`, `quotaWarnings`) are placeholders for
/// dynamic sections whose data arrives inside the payload; Task 7 wires
/// their editing commands.
public enum PaneRow: Codable, Equatable, Sendable {
    case section(title: String)
    case header(displayName: String, subtitle: String?, iconSVG: String?, accentColorHex: String)
    case toggle(key: String, title: String, value: Bool)
    case picker(key: String, title: String, options: [PaneOption], selected: String, visibleWhen: RowCondition?)
    case field(
        key: String, title: String, value: String, secure: Bool,
        placeholder: String?, visibleWhen: RowCondition?)
    /// A line of guidance under the field it follows. Text only — it carries
    /// no key and no binding.
    case hint(text: String)
    case info(title: String, value: String)
    case link(title: String, url: String)
    case button(action: String, title: String)
    case tokenAccounts(providerID: String)
    case managedCodexAccounts(providerID: String)
    case quotaWarnings(providerID: String)
    case organizations(providerID: String)
    case claudeSwap(providerID: String)
    /// Marker for the Usage & Spend pane's live dashboard; the data rides in
    /// `SettingsPayload.costs`, same pattern as the provider collection rows.
    case spendDashboard

    private enum CodingKeys: String, CodingKey {
        case kind
        case title, subtitle, key, value, options, selected, secure, url, action
        case placeholder, text
        case displayName, iconSVG, accentColorHex, providerID, visibleWhen
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "section":
            self = .section(title: try c.decode(String.self, forKey: .title))
        case "header":
            self = .header(
                displayName: try c.decode(String.self, forKey: .displayName),
                subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle),
                iconSVG: try c.decodeIfPresent(String.self, forKey: .iconSVG),
                accentColorHex: try c.decode(String.self, forKey: .accentColorHex))
        case "toggle":
            self = .toggle(
                key: try c.decode(String.self, forKey: .key),
                title: try c.decode(String.self, forKey: .title),
                value: try c.decode(Bool.self, forKey: .value))
        case "picker":
            self = .picker(
                key: try c.decode(String.self, forKey: .key),
                title: try c.decode(String.self, forKey: .title),
                options: try c.decode([PaneOption].self, forKey: .options),
                selected: try c.decode(String.self, forKey: .selected),
                visibleWhen: try c.decodeIfPresent(RowCondition.self, forKey: .visibleWhen))
        case "field":
            self = .field(
                key: try c.decode(String.self, forKey: .key),
                title: try c.decode(String.self, forKey: .title),
                value: try c.decode(String.self, forKey: .value),
                secure: try c.decode(Bool.self, forKey: .secure),
                // Absent in payloads written before the copy table existed.
                placeholder: try c.decodeIfPresent(String.self, forKey: .placeholder),
                visibleWhen: try c.decodeIfPresent(RowCondition.self, forKey: .visibleWhen))
        case "hint":
            self = .hint(text: try c.decode(String.self, forKey: .text))
        case "info":
            self = .info(
                title: try c.decode(String.self, forKey: .title),
                value: try c.decode(String.self, forKey: .value))
        case "link":
            self = .link(
                title: try c.decode(String.self, forKey: .title),
                url: try c.decode(String.self, forKey: .url))
        case "button":
            self = .button(
                action: try c.decode(String.self, forKey: .action),
                title: try c.decode(String.self, forKey: .title))
        case "tokenAccounts":
            self = .tokenAccounts(providerID: try c.decode(String.self, forKey: .providerID))
        case "managedCodexAccounts":
            self = .managedCodexAccounts(providerID: try c.decode(String.self, forKey: .providerID))
        case "quotaWarnings":
            self = .quotaWarnings(providerID: try c.decode(String.self, forKey: .providerID))
        case "organizations":
            self = .organizations(providerID: try c.decode(String.self, forKey: .providerID))
        case "claudeSwap":
            self = .claudeSwap(providerID: try c.decode(String.self, forKey: .providerID))
        case "spendDashboard":
            self = .spendDashboard
        case let unknown:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c,
                debugDescription: "Unknown pane row kind: \(unknown)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .section(title):
            try c.encode("section", forKey: .kind)
            try c.encode(title, forKey: .title)
        case let .header(displayName, subtitle, iconSVG, accentColorHex):
            try c.encode("header", forKey: .kind)
            try c.encode(displayName, forKey: .displayName)
            try c.encodeIfPresent(subtitle, forKey: .subtitle)
            try c.encodeIfPresent(iconSVG, forKey: .iconSVG)
            try c.encode(accentColorHex, forKey: .accentColorHex)
        case let .toggle(key, title, value):
            try c.encode("toggle", forKey: .kind)
            try c.encode(key, forKey: .key)
            try c.encode(title, forKey: .title)
            try c.encode(value, forKey: .value)
        case let .picker(key, title, options, selected, visibleWhen):
            try c.encode("picker", forKey: .kind)
            try c.encode(key, forKey: .key)
            try c.encode(title, forKey: .title)
            try c.encode(options, forKey: .options)
            try c.encode(selected, forKey: .selected)
            try c.encodeIfPresent(visibleWhen, forKey: .visibleWhen)
        case let .field(key, title, value, secure, placeholder, visibleWhen):
            try c.encode("field", forKey: .kind)
            try c.encode(key, forKey: .key)
            try c.encode(title, forKey: .title)
            try c.encode(value, forKey: .value)
            try c.encode(secure, forKey: .secure)
            try c.encodeIfPresent(placeholder, forKey: .placeholder)
            try c.encodeIfPresent(visibleWhen, forKey: .visibleWhen)
        case let .hint(text):
            try c.encode("hint", forKey: .kind)
            try c.encode(text, forKey: .text)
        case let .info(title, value):
            try c.encode("info", forKey: .kind)
            try c.encode(title, forKey: .title)
            try c.encode(value, forKey: .value)
        case let .link(title, url):
            try c.encode("link", forKey: .kind)
            try c.encode(title, forKey: .title)
            try c.encode(url, forKey: .url)
        case let .button(action, title):
            try c.encode("button", forKey: .kind)
            try c.encode(action, forKey: .action)
            try c.encode(title, forKey: .title)
        case let .tokenAccounts(providerID):
            try c.encode("tokenAccounts", forKey: .kind)
            try c.encode(providerID, forKey: .providerID)
        case let .managedCodexAccounts(providerID):
            try c.encode("managedCodexAccounts", forKey: .kind)
            try c.encode(providerID, forKey: .providerID)
        case let .quotaWarnings(providerID):
            try c.encode("quotaWarnings", forKey: .kind)
            try c.encode(providerID, forKey: .providerID)
        case let .organizations(providerID):
            try c.encode("organizations", forKey: .kind)
            try c.encode(providerID, forKey: .providerID)
        case let .claudeSwap(providerID):
            try c.encode("claudeSwap", forKey: .kind)
            try c.encode(providerID, forKey: .providerID)
        case .spendDashboard:
            try c.encode("spendDashboard", forKey: .kind)
        }
    }
}

/// A generated pane: the provider id plus its rows.
public struct ProviderPanePayload: Codable, Equatable, Sendable {
    public var id: String
    public var rows: [PaneRow]
    /// Collection data the dynamic rows render. Carried alongside the rows
    /// rather than inside them so the generic renderer stays unaware of it.
    public var tokenAccounts: ProviderTokenAccountData?
    public var quotaWarnings: QuotaWarningConfig?

    public init(
        id: String,
        rows: [PaneRow],
        tokenAccounts: ProviderTokenAccountData? = nil,
        quotaWarnings: QuotaWarningConfig? = nil)
    {
        self.id = id
        self.rows = rows
        self.tokenAccounts = tokenAccounts
        self.quotaWarnings = quotaWarnings
    }
}
