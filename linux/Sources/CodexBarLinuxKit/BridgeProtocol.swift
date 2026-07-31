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

    private enum CodingKeys: String, CodingKey {
        case type
        case provider
        case id
        case url
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
        }
    }
}

/// Messages sent from Swift to the web UI.
public enum BridgeEvent: Codable, Equatable, Sendable {
    case snapshot(ProviderSnapshotPayload)
    case refreshStarted(provider: String?)
    case error(message: String)

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
