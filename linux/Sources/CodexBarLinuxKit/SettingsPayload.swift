import CodexBarCore
import Foundation

/// Everything the settings window renders, in one message.
public struct SettingsPayload: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var settings: LinuxSettings
    public var general: [GeneralPane]
    public var providers: [ProviderPanePayload]
    public var managedCodexAccounts: [ManagedCodexAccountView]
    public var kiloOrganizations: KiloOrganizationsPayload
    public var claudeSwap: ClaudeSwapPayload
    public var hooks: HooksConfig
    /// Providers with an available cost snapshot; the Usage & Spend pane
    /// groups and renders these. Already identity-scrubbed when the user's
    /// settings demand it — the web layer never re-adds detail.
    public var costs: [ProviderCostView]
    public var localization: LocalizationPayload

    public init(
        generatedAt: Date,
        settings: LinuxSettings,
        general: [GeneralPane],
        providers: [ProviderPanePayload],
        managedCodexAccounts: [ManagedCodexAccountView] = [],
        kiloOrganizations: KiloOrganizationsPayload = KiloOrganizationsPayload(),
        claudeSwap: ClaudeSwapPayload = ClaudeSwapPayload(executablePath: nil, accounts: [], errorMessage: nil),
        hooks: HooksConfig,
        costs: [ProviderCostView] = [],
        localization: LocalizationPayload)
    {
        self.localization = localization
        self.generatedAt = generatedAt
        self.settings = settings
        self.general = general
        self.providers = providers
        self.managedCodexAccounts = managedCodexAccounts
        self.kiloOrganizations = kiloOrganizations
        self.claudeSwap = claudeSwap
        self.hooks = hooks
        self.costs = costs
    }
}
