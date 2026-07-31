import CodexBarCore
import Foundation

/// Messages sent from the web UI to Swift.
///
/// Encoded as `{"type": "<case>", ...}` so the JS side stays readable.
public enum BridgeCommand: Codable, Equatable, Sendable {
    case ready
    case refresh(provider: String?)
    case selectProvider(id: String)
    case openURL(String)
    case quit
    case openSettings
    case settingsReady
    case updateProviderConfig(id: String, patch: ProviderConfigPatch)
    case updateSettings(LinuxSettings)
    case updateHooks(HooksConfig)
    case openConfigFolder
    case replaceTokenAccounts(providerID: String, data: ProviderTokenAccountData?)
    case updateQuotaWarnings(providerID: String, config: QuotaWarningConfig?)

    private enum CodingKeys: String, CodingKey {
        case type
        case provider
        case id
        case url
        case patch
        case settings
        case hooks
        case providerID
        case data
        case config
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "ready":
            self = .ready
        case "refresh":
            self = .refresh(provider: try container.decodeIfPresent(String.self, forKey: .provider))
        case "selectProvider":
            self = .selectProvider(id: try container.decode(String.self, forKey: .id))
        case "openURL":
            self = .openURL(try container.decode(String.self, forKey: .url))
        case "quit":
            self = .quit
        case "openSettings":
            self = .openSettings
        case "settingsReady":
            self = .settingsReady
        case "updateProviderConfig":
            self = .updateProviderConfig(
                id: try container.decode(String.self, forKey: .id),
                patch: try container.decode(ProviderConfigPatch.self, forKey: .patch))
        case "updateSettings":
            self = .updateSettings(try container.decode(LinuxSettings.self, forKey: .settings))
        case "updateHooks":
            self = .updateHooks(try container.decode(HooksConfig.self, forKey: .hooks))
        case "openConfigFolder":
            self = .openConfigFolder
        // For these two an absent/null value means "clear the override",
        // unlike ProviderConfigPatch where an omitted key means "unchanged".
        case "replaceTokenAccounts":
            self = .replaceTokenAccounts(
                providerID: try container.decode(String.self, forKey: .providerID),
                data: try container.decodeIfPresent(ProviderTokenAccountData.self, forKey: .data))
        case "updateQuotaWarnings":
            self = .updateQuotaWarnings(
                providerID: try container.decode(String.self, forKey: .providerID),
                config: try container.decodeIfPresent(QuotaWarningConfig.self, forKey: .config))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown bridge command type: \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ready:
            try container.encode("ready", forKey: .type)
        case let .refresh(provider):
            try container.encode("refresh", forKey: .type)
            try container.encodeIfPresent(provider, forKey: .provider)
        case let .selectProvider(id):
            try container.encode("selectProvider", forKey: .type)
            try container.encode(id, forKey: .id)
        case let .openURL(url):
            try container.encode("openURL", forKey: .type)
            try container.encode(url, forKey: .url)
        case .quit:
            try container.encode("quit", forKey: .type)
        case .openSettings:
            try container.encode("openSettings", forKey: .type)
        case .settingsReady:
            try container.encode("settingsReady", forKey: .type)
        case let .updateProviderConfig(id, patch):
            try container.encode("updateProviderConfig", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(patch, forKey: .patch)
        case let .updateSettings(settings):
            try container.encode("updateSettings", forKey: .type)
            try container.encode(settings, forKey: .settings)
        case let .updateHooks(hooks):
            try container.encode("updateHooks", forKey: .type)
            try container.encode(hooks, forKey: .hooks)
        case .openConfigFolder:
            try container.encode("openConfigFolder", forKey: .type)
        case let .replaceTokenAccounts(providerID, data):
            try container.encode("replaceTokenAccounts", forKey: .type)
            try container.encode(providerID, forKey: .providerID)
            try container.encodeIfPresent(data, forKey: .data)
        case let .updateQuotaWarnings(providerID, config):
            try container.encode("updateQuotaWarnings", forKey: .type)
            try container.encode(providerID, forKey: .providerID)
            try container.encodeIfPresent(config, forKey: .config)
        }
    }
}

/// Messages sent from Swift to the web UI.
public enum BridgeEvent: Codable, Equatable, Sendable {
    case snapshot(ProviderSnapshotPayload)
    case refreshStarted(provider: String?)
    case error(message: String)
    case settings(SettingsPayload)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
        case provider
        case message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "snapshot":
            self = .snapshot(try container.decode(ProviderSnapshotPayload.self, forKey: .payload))
        case "refreshStarted":
            self = .refreshStarted(provider: try container.decodeIfPresent(String.self, forKey: .provider))
        case "error":
            self = .error(message: try container.decode(String.self, forKey: .message))
        case "settings":
            self = .settings(try container.decode(SettingsPayload.self, forKey: .payload))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown bridge event type: \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .snapshot(payload):
            try container.encode("snapshot", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .refreshStarted(provider):
            try container.encode("refreshStarted", forKey: .type)
            try container.encodeIfPresent(provider, forKey: .provider)
        case let .error(message):
            try container.encode("error", forKey: .type)
            try container.encode(message, forKey: .message)
        case let .settings(payload):
            try container.encode("settings", forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

/// Escaping helpers for embedding JSON inside an evaluated script.
public enum BridgeScriptEncoding {
    /// Wraps `value` as a JavaScript string literal, escaping backslashes and quotes.
    /// Backslashes must be escaped first, or the quote escapes get mangled.
    public static func javaScriptStringLiteral(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }
}
