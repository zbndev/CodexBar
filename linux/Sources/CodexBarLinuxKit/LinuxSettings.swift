import Foundation

/// How the tray label is computed. The Linux tray shows one icon plus one
/// label; the macOS token-layout editor has no counterpart here.
public enum TrayLabelStyle: String, Codable, CaseIterable, Sendable {
    case none
    case highestPercent
}

public enum RefreshInterval: String, Codable, CaseIterable, Sendable {
    case manual
    case adaptive
    case adaptiveAgentAware
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes

    public var seconds: Double? {
        switch self {
        case .manual: nil
        case .adaptive, .adaptiveAgentAware: nil
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1800
        }
    }
}

/// Every UI preference the Linux app honours.
///
/// On macOS these live in `SettingsStore` (UserDefaults); on Linux there is
/// no UserDefaults, so they live in their own file next to the shared
/// config. Provider-specific settings are NOT here — they belong to
/// `ProviderConfig` in the shared `config.json` and travel through
/// `ProviderConfigPatch`.
public struct LinuxSettings: Codable, Equatable, Sendable {
    /// nil = follow the system locale.
    public var language: String?
    public var refreshInterval: RefreshInterval
    public var refreshOnOpen: Bool
    public var statusChecksEnabled: Bool
    public var launchAtLogin: Bool

    // Tray
    public var trayLabelStyle: TrayLabelStyle

    // Popup
    public var usageBarsShowUsed: Bool
    public var resetTimesShowAbsolute: Bool
    public var showCreditsAndExtraUsage: Bool
    /// Token-cost estimates are opt-in, matching upstream's `costUsageEnabled`.
    /// Deliberately separate from `showCreditsAndExtraUsage`: credits and extra
    /// usage are a balance the provider reports, this is an estimate derived
    /// from local token counts, and on a subscription plan it bills nothing.
    public var costUsageEnabled: Bool

    // Notifications (delivery itself is M5; the toggles persist now)
    public var sessionQuotaNotificationsEnabled: Bool
    public var quotaWarningNotificationsEnabled: Bool
    public var predictivePaceWarningsEnabled: Bool
    public var quotaWarningSessionEnabled: Bool
    public var quotaWarningWeeklyEnabled: Bool
    public var quotaWarningSessionThresholds: [Int]
    public var quotaWarningWeeklyThresholds: [Int]
    public var quotaWarningSoundEnabled: Bool
    public var quotaWarningOnScreenAlertEnabled: Bool

    // Advanced
    public var hidePersonalInfo: Bool
    /// Opt-in, matching upstream's `agentSessionsEnabled`. The scan runs
    /// regardless — `.adaptiveAgentAware` refresh feeds on its activity
    /// timestamp — so this gates publication only, in `ProviderSnapshotPayload`.
    public var agentSessionsEnabled: Bool
    public var includeFileOnlySessions: Bool
    public var providerStorageFootprintsEnabled: Bool
    public var debugMenuEnabled: Bool

    public init() {
        self.language = nil
        self.refreshInterval = .fiveMinutes
        self.refreshOnOpen = true
        self.statusChecksEnabled = true
        self.launchAtLogin = false
        self.trayLabelStyle = .highestPercent
        self.usageBarsShowUsed = true
        self.resetTimesShowAbsolute = false
        self.showCreditsAndExtraUsage = true
        self.costUsageEnabled = false
        self.sessionQuotaNotificationsEnabled = true
        self.quotaWarningNotificationsEnabled = true
        self.predictivePaceWarningsEnabled = true
        self.quotaWarningSessionEnabled = true
        self.quotaWarningWeeklyEnabled = true
        self.quotaWarningSessionThresholds = [50, 20]
        self.quotaWarningWeeklyThresholds = [50, 20]
        self.quotaWarningSoundEnabled = true
        self.quotaWarningOnScreenAlertEnabled = false
        self.hidePersonalInfo = false
        self.agentSessionsEnabled = false
        self.includeFileOnlySessions = true
        self.providerStorageFootprintsEnabled = false
        self.debugMenuEnabled = false
    }

    /// Tolerant decoding: every key is optional on the wire, anything
    /// absent falls back to `init()`'s default, and unknown keys are simply
    /// never read. This keeps settings forward- and backward-compatible
    /// without a version field.
    public init(from decoder: any Decoder) throws {
        let defaults = LinuxSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys, or fallback: T) throws -> T {
            try container.decodeIfPresent(type, forKey: key) ?? fallback
        }
        self.language = try container.decodeIfPresent(String.self, forKey: .language) ?? defaults.language
        self.refreshInterval = try value(RefreshInterval.self, .refreshInterval, or: defaults.refreshInterval)
        self.refreshOnOpen = try value(Bool.self, .refreshOnOpen, or: defaults.refreshOnOpen)
        self.statusChecksEnabled = try value(Bool.self, .statusChecksEnabled, or: defaults.statusChecksEnabled)
        self.launchAtLogin = try value(Bool.self, .launchAtLogin, or: defaults.launchAtLogin)
        self.trayLabelStyle = try value(TrayLabelStyle.self, .trayLabelStyle, or: defaults.trayLabelStyle)
        self.usageBarsShowUsed = try value(Bool.self, .usageBarsShowUsed, or: defaults.usageBarsShowUsed)
        self.resetTimesShowAbsolute = try value(
            Bool.self, .resetTimesShowAbsolute, or: defaults.resetTimesShowAbsolute)
        self.showCreditsAndExtraUsage = try value(
            Bool.self, .showCreditsAndExtraUsage, or: defaults.showCreditsAndExtraUsage)
        self.costUsageEnabled = try value(Bool.self, .costUsageEnabled, or: defaults.costUsageEnabled)
        self.sessionQuotaNotificationsEnabled = try value(
            Bool.self, .sessionQuotaNotificationsEnabled, or: defaults.sessionQuotaNotificationsEnabled)
        self.quotaWarningNotificationsEnabled = try value(
            Bool.self, .quotaWarningNotificationsEnabled, or: defaults.quotaWarningNotificationsEnabled)
        self.predictivePaceWarningsEnabled = try value(
            Bool.self, .predictivePaceWarningsEnabled, or: defaults.predictivePaceWarningsEnabled)
        self.quotaWarningSessionEnabled = try value(
            Bool.self, .quotaWarningSessionEnabled, or: defaults.quotaWarningSessionEnabled)
        self.quotaWarningWeeklyEnabled = try value(
            Bool.self, .quotaWarningWeeklyEnabled, or: defaults.quotaWarningWeeklyEnabled)
        self.quotaWarningSessionThresholds = try value(
            [Int].self, .quotaWarningSessionThresholds, or: defaults.quotaWarningSessionThresholds)
        self.quotaWarningWeeklyThresholds = try value(
            [Int].self, .quotaWarningWeeklyThresholds, or: defaults.quotaWarningWeeklyThresholds)
        self.quotaWarningSoundEnabled = try value(
            Bool.self, .quotaWarningSoundEnabled, or: defaults.quotaWarningSoundEnabled)
        self.quotaWarningOnScreenAlertEnabled = try value(
            Bool.self, .quotaWarningOnScreenAlertEnabled, or: defaults.quotaWarningOnScreenAlertEnabled)
        self.hidePersonalInfo = try value(Bool.self, .hidePersonalInfo, or: defaults.hidePersonalInfo)
        self.agentSessionsEnabled = try value(
            Bool.self, .agentSessionsEnabled, or: defaults.agentSessionsEnabled)
        self.includeFileOnlySessions = try value(
            Bool.self, .includeFileOnlySessions, or: defaults.includeFileOnlySessions)
        self.providerStorageFootprintsEnabled = try value(
            Bool.self, .providerStorageFootprintsEnabled, or: defaults.providerStorageFootprintsEnabled)
        self.debugMenuEnabled = try value(Bool.self, .debugMenuEnabled, or: defaults.debugMenuEnabled)
    }
}
