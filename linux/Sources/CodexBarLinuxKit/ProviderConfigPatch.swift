import CodexBarCore
import Foundation

/// A partial edit to a `ProviderConfig`.
///
/// Optionals mean "not edited". Empty strings on text fields mean "clear"
/// — that is how the renderer deletes an API key or cookie header, and it
/// matches how the macOS fields behave. CodingKeys are the row keys from
/// `PaneRow`; keep them in sync.
public struct ProviderConfigPatch: Codable, Equatable, Sendable {
    public var enabled: Bool?
    public var source: ProviderSourceMode?
    public var extrasEnabled: Bool?
    public var apiKey: String?
    public var secretKey: String?
    public var cookieHeader: String?
    public var cookieSource: ProviderCookieSource?
    public var region: String?
    public var workspaceID: String?
    public var enterpriseHost: String?
    public var awsProfile: String?
    public var awsAuthMode: String?
    public var antigravityPrioritizeExhaustedQuotas: Bool?
    public var deepseekProfileID: String?
    public var deepseekProfileScope: String?
    public init() {}

    /// Mutates a copy, never reconstructs the value. Upstream can add a new
    /// ProviderConfig property without an older Linux settings build
    /// silently resetting it to nil.
    public func applying(to config: ProviderConfig) -> ProviderConfig {
        var result = config
        if let value = self.enabled { result.enabled = value }
        if let value = self.source { result.source = value }
        if let value = self.extrasEnabled { result.extrasEnabled = value }
        if let value = self.apiKey { result.apiKey = value.isEmpty ? nil : value }
        if let value = self.secretKey { result.secretKey = value.isEmpty ? nil : value }
        if let value = self.cookieHeader { result.cookieHeader = value.isEmpty ? nil : value }
        if let value = self.cookieSource { result.cookieSource = value }
        if let value = self.region { result.region = value.isEmpty ? nil : value }
        if let value = self.workspaceID { result.workspaceID = value.isEmpty ? nil : value }
        if let value = self.enterpriseHost { result.enterpriseHost = value.isEmpty ? nil : value }
        if let value = self.awsProfile { result.awsProfile = value.isEmpty ? nil : value }
        if let value = self.awsAuthMode { result.awsAuthMode = value.isEmpty ? nil : value }
        if let value = self.antigravityPrioritizeExhaustedQuotas {
            result.antigravityPrioritizeExhaustedQuotas = value
        }
        if let value = self.deepseekProfileID { result.deepseekProfileID = value.isEmpty ? nil : value }
        if let value = self.deepseekProfileScope { result.deepseekProfileScope = value.isEmpty ? nil : value }
        return result
    }
}
