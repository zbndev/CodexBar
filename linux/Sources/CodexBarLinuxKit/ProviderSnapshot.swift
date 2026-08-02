import CodexBarCore
import Foundation

extension ProviderColor {
    /// `#RRGGBB`, for handing straight to CSS.
    public var hexString: String {
        func channel(_ value: Double) -> Int {
            Int((value * 255).rounded()).clamped(to: 0...255)
        }
        return String(format: "#%02X%02X%02X", channel(self.red), channel(self.green), channel(self.blue))
    }
}

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

public enum ProviderOperationalStatus: String, Codable, Equatable, Sendable {
    case unknown
    case available
    case unavailable
}

/// One usage window as the UI needs it.
public struct ProviderWindowView: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var resetDescription: String?

    public init(
        id: String,
        title: String,
        usedPercent: Double,
        resetsAt: Date? = nil,
        resetDescription: String? = nil)
    {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }
}

/// One provider card.
public struct ProviderView: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var iconResourceName: String
    public var iconSVG: String?
    public var accentColorHex: String
    public var enabled: Bool
    public var windows: [ProviderWindowView]
    public var plan: String?
    public var accountEmail: String?
    public var updatedAt: Date?
    public var sourceLabel: String?
    public var errorMessage: String?
    public var isLoading: Bool
    public var dashboardURL: String?
    public var statusPageURL: String?
    public var changelogURL: String?
    public var operationalStatus: ProviderOperationalStatus
    /// The latest cost scan, when the provider supports one. Attached at
    /// payload time by `LinuxUsageStore`, never by the fetch path.
    public var cost: ProviderCostView?
    /// Persisted utilization samples per window, for the history charts.
    public var history: [UtilizationHistorySeries]?

    public init(
        id: String,
        displayName: String,
        iconResourceName: String,
        iconSVG: String? = nil,
        accentColorHex: String,
        enabled: Bool,
        windows: [ProviderWindowView] = [],
        plan: String? = nil,
        accountEmail: String? = nil,
        updatedAt: Date? = nil,
        sourceLabel: String? = nil,
        errorMessage: String? = nil,
        isLoading: Bool = false,
        dashboardURL: String? = nil,
        statusPageURL: String? = nil,
        changelogURL: String? = nil,
        operationalStatus: ProviderOperationalStatus = .unknown,
        cost: ProviderCostView? = nil,
        history: [UtilizationHistorySeries]? = nil)
    {
        self.id = id
        self.displayName = displayName
        self.iconResourceName = iconResourceName
        self.iconSVG = iconSVG
        self.accentColorHex = accentColorHex
        self.enabled = enabled
        self.windows = windows
        self.plan = plan
        self.accountEmail = accountEmail
        self.updatedAt = updatedAt
        self.sourceLabel = sourceLabel
        self.errorMessage = errorMessage
        self.isLoading = isLoading
        self.dashboardURL = dashboardURL
        self.statusPageURL = statusPageURL
        self.changelogURL = changelogURL
        self.operationalStatus = operationalStatus
        self.cost = cost
        self.history = history
    }
}

/// Display-only local coding-session data. Scanner paths, process ids, and host
/// names intentionally have no representation in this payload.
public struct AgentSessionView: Codable, Equatable, Sendable {
    public let id: String
    public let provider: String
    public let state: String
    public let projectName: String?
    public let sessionName: String?
    public let lastActivityAt: Date

    public init(
        id: String,
        provider: String,
        state: String,
        projectName: String?,
        sessionName: String?,
        lastActivityAt: Date)
    {
        self.id = id
        self.provider = provider
        self.state = state
        self.projectName = projectName
        self.sessionName = sessionName
        self.lastActivityAt = lastActivityAt
    }
}

public struct AgentSessionsPayload: Codable, Equatable, Sendable {
    public let scannedAt: Date
    public let sessions: [AgentSessionView]
    public let errorMessage: String?

    public init(scannedAt: Date, sessions: [AgentSessionView], errorMessage: String?) {
        self.scannedAt = scannedAt
        self.sessions = sessions
        self.errorMessage = errorMessage
    }
}

/// The whole UI state in one message.
public struct ProviderSnapshotPayload: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var providers: [ProviderView]
    /// The popup only ever receives snapshots, so the catalog has to ride
    /// along here — `SettingsPayload` reaches `settings.js` alone.
    public var localization: LocalizationPayload
    public var display: DisplayPreferences
    public var agentSessions: AgentSessionsPayload?

    public init(
        generatedAt: Date,
        providers: [ProviderView],
        localization: LocalizationPayload = LocalizationCatalog.load(locale: nil),
        display: DisplayPreferences = DisplayPreferences(settings: LinuxSettings()),
        agentSessions: AgentSessionsPayload? = nil)
    {
        self.generatedAt = generatedAt
        self.providers = providers
        self.localization = localization
        self.display = display
        self.agentSessions = agentSessions
    }

    /// Identity hiding must be a data guarantee, not a rendering habit: with
    /// it on, project paths and session ids never cross the bridge at all.
    /// Daily aggregates stay — the charts need them and they carry no identity.
    public func hidingPersonalInfo(_ enabled: Bool) -> ProviderSnapshotPayload {
        guard enabled else { return self }
        var copy = self
        copy.providers = self.providers.map { provider in
            var provider = provider
            provider.cost = provider.cost?.hidingPersonalInfo()
            return provider
        }
        copy.agentSessions = self.agentSessions.map { payload in
            AgentSessionsPayload(
                scannedAt: payload.scannedAt,
                sessions: payload.sessions.map { session in
                    AgentSessionView(
                        id: session.id,
                        provider: session.provider,
                        state: session.state,
                        projectName: nil,
                        sessionName: nil,
                        lastActivityAt: session.lastActivityAt)
                },
                errorMessage: payload.errorMessage)
        }
        return copy
    }

    /// The Agent Sessions section is opt-in, matching upstream's
    /// `agentSessionsEnabled` default of `false`. The gate sits here rather
    /// than in the renderer for the same reason `hidingPersonalInfo` does:
    /// with the section off the payload is absent, not empty, so project names
    /// and session ids never cross the bridge at all.
    ///
    /// The scan itself is not gated. `.adaptiveAgentAware` refresh feeds on
    /// `LinuxAgentSessionsStore.lastCodingActivityAt`, and upstream draws the
    /// same line — see `AgentSessionsStore.localMonitoringEnabled`.
    public func withAgentSessions(
        _ payload: AgentSessionsPayload,
        enabled: Bool) -> ProviderSnapshotPayload
    {
        var copy = self
        copy.agentSessions = enabled ? payload : nil
        return copy
    }
}

/// The popup-facing subset of `LinuxSettings`. Sent with every snapshot so
/// display changes take effect without a restart.
public struct DisplayPreferences: Codable, Equatable, Sendable {
    public var usageBarsShowUsed: Bool
    public var resetTimesShowAbsolute: Bool
    public var showCreditsAndExtraUsage: Bool
    public var costUsageEnabled: Bool
    public var hidePersonalInfo: Bool

    public init(settings: LinuxSettings) {
        self.usageBarsShowUsed = settings.usageBarsShowUsed
        self.resetTimesShowAbsolute = settings.resetTimesShowAbsolute
        self.showCreditsAndExtraUsage = settings.showCreditsAndExtraUsage
        self.costUsageEnabled = settings.costUsageEnabled
        self.hidePersonalInfo = settings.hidePersonalInfo
    }
}
