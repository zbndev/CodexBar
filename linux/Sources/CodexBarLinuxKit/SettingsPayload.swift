import CodexBarCore
import Foundation

/// Everything the settings window renders, in one message.
public struct SettingsPayload: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var settings: LinuxSettings
    public var providers: [ProviderPanePayload]
    public var hooks: HooksConfig

    public init(
        generatedAt: Date,
        settings: LinuxSettings,
        providers: [ProviderPanePayload],
        hooks: HooksConfig)
    {
        self.generatedAt = generatedAt
        self.settings = settings
        self.providers = providers
        self.hooks = hooks
    }
}
