import CodexBarCore
import Foundation

/// One of the nine general panes.
public struct GeneralPane: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var rows: [PaneRow]

    public init(id: String, title: String, rows: [PaneRow]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}

/// The general settings panes, described as `PaneRow` lists so the web
/// renderer handles them identically to provider panes.
///
/// Row keys are `LinuxSettings` property names — the renderer writes edits
/// back by key, so a mismatch here is a silently dropped edit. The
/// Mirror-based test in SettingsPayloadTests guards exactly that.
public enum GeneralPaneCatalog {
    public static func panes(settings: LinuxSettings, hooks: HooksConfig) -> [GeneralPane] {
        [
            self.generalPane(settings),
            GeneralPane(id: "spend", title: "Usage & Spend", rows: [
                .toggle(
                    key: "showCreditsAndExtraUsage",
                    title: "Show credits and extra usage",
                    value: settings.showCreditsAndExtraUsage),
                .info(title: "Spend dashboard", value: "Arrives with M5"),
            ]),
            self.notificationsPane(settings),
            GeneralPane(id: "tray", title: "Tray", rows: [
                .picker(
                    key: "trayLabelStyle",
                    title: "Tray label",
                    options: [
                        PaneOption(id: "none", title: "Icon only"),
                        PaneOption(id: "highestPercent", title: "Highest usage %"),
                    ],
                    selected: settings.trayLabelStyle.rawValue,
                    visibleWhen: nil),
            ]),
            GeneralPane(id: "menu", title: "Popup", rows: [
                .picker(
                    key: "usageBarsShowUsed",
                    title: "Usage bars fill",
                    options: [
                        PaneOption(id: "true", title: "Used"),
                        PaneOption(id: "false", title: "Remaining"),
                    ],
                    selected: settings.usageBarsShowUsed ? "true" : "false",
                    visibleWhen: nil),
                .picker(
                    key: "resetTimesShowAbsolute",
                    title: "Reset times",
                    options: [
                        PaneOption(id: "false", title: "Relative (in 3h 20m)"),
                        PaneOption(id: "true", title: "Absolute (at 14:30)"),
                    ],
                    selected: settings.resetTimesShowAbsolute ? "true" : "false",
                    visibleWhen: nil),
                .toggle(
                    key: "showCreditsAndExtraUsage",
                    title: "Show credits and extra usage",
                    value: settings.showCreditsAndExtraUsage),
            ]),
            GeneralPane(id: "advanced", title: "Advanced", rows: [
                .toggle(
                    key: "hidePersonalInfo",
                    title: "Hide personal information",
                    value: settings.hidePersonalInfo),
                .toggle(
                    key: "providerStorageFootprintsEnabled",
                    title: "Show provider storage usage",
                    value: settings.providerStorageFootprintsEnabled),
                .toggle(
                    key: "debugMenuEnabled",
                    title: "Show debug settings",
                    value: settings.debugMenuEnabled),
            ]),
            GeneralPane(id: "hooks", title: "Hooks", rows: [
                .toggle(key: "hooksEnabled", title: "Enable hooks", value: hooks.enabled),
            ]),
            self.aboutPane(),
            GeneralPane(id: "debug", title: "Debug", rows: [
                .info(title: "Config file", value: CodexBarConfigStore.defaultURL().path),
                .button(action: "openConfigFolder", title: "Open config folder"),
                .button(action: "refresh", title: "Refresh all providers now"),
            ]),
        ].filter { $0.id != "debug" || settings.debugMenuEnabled }
    }

    private static func generalPane(_ settings: LinuxSettings) -> GeneralPane {
        GeneralPane(id: "general", title: "General", rows: [
            .picker(
                key: "language",
                title: "Language",
                options: [PaneOption(id: "", title: "System language")] +
                    LocalizationCatalog.supportedLocales.map { PaneOption(id: $0, title: $0) },
                selected: settings.language ?? "",
                visibleWhen: nil),
            .picker(
                key: "refreshInterval",
                title: "Refresh interval",
                options: RefreshInterval.allCases.map {
                    PaneOption(id: $0.rawValue, title: Self.refreshTitle($0))
                },
                selected: settings.refreshInterval.rawValue,
                visibleWhen: nil),
            .toggle(
                key: "refreshOnOpen",
                title: "Refresh all providers when opening the popup",
                value: settings.refreshOnOpen),
            .toggle(
                key: "statusChecksEnabled",
                title: "Check provider status",
                value: settings.statusChecksEnabled),
            .button(action: "refresh", title: "Refresh all providers now"),
            .button(action: "quit", title: "Quit CodexBar"),
        ])
    }

    private static func notificationsPane(_ settings: LinuxSettings) -> GeneralPane {
        GeneralPane(id: "notifications", title: "Notifications", rows: [
            .toggle(
                key: "sessionQuotaNotificationsEnabled",
                title: "Quota depleted",
                value: settings.sessionQuotaNotificationsEnabled),
            .toggle(
                key: "quotaWarningNotificationsEnabled",
                title: "Threshold warnings",
                value: settings.quotaWarningNotificationsEnabled),
            .toggle(
                key: "predictivePaceWarningsEnabled",
                title: "Predictive pace warnings",
                value: settings.predictivePaceWarningsEnabled),
            .section(title: "Session window"),
            .toggle(
                key: "quotaWarningSessionEnabled",
                title: "Enabled",
                value: settings.quotaWarningSessionEnabled),
            .field(
                key: "quotaWarningSessionThresholds",
                title: "Thresholds (%, comma-separated)",
                value: settings.quotaWarningSessionThresholds.map(String.init).joined(separator: ","),
                secure: false,
                visibleWhen: nil),
            .section(title: "Weekly window"),
            .toggle(
                key: "quotaWarningWeeklyEnabled",
                title: "Enabled",
                value: settings.quotaWarningWeeklyEnabled),
            .field(
                key: "quotaWarningWeeklyThresholds",
                title: "Thresholds (%, comma-separated)",
                value: settings.quotaWarningWeeklyThresholds.map(String.init).joined(separator: ","),
                secure: false,
                visibleWhen: nil),
            .section(title: "Delivery"),
            .toggle(
                key: "quotaWarningSoundEnabled",
                title: "Sound",
                value: settings.quotaWarningSoundEnabled),
            .toggle(
                key: "quotaWarningOnScreenAlertEnabled",
                title: "On-screen alert",
                value: settings.quotaWarningOnScreenAlertEnabled),
        ])
    }

    private static func aboutPane() -> GeneralPane {
        GeneralPane(id: "about", title: "About", rows: [
            .info(title: "Application", value: "CodexBar for Linux"),
            .info(title: "Version", value: LinuxAppInfo.version),
            .link(title: "GitHub", url: "https://github.com/steipete/CodexBar"),
            .link(title: "Website", url: "https://codexbar.app"),
            .link(title: "Documentation", url: "https://github.com/steipete/CodexBar#readme"),
        ])
    }

    private static func refreshTitle(_ interval: RefreshInterval) -> String {
        switch interval {
        case .manual: "Manual"
        case .oneMinute: "Every minute"
        case .twoMinutes: "Every 2 minutes"
        case .fiveMinutes: "Every 5 minutes"
        case .fifteenMinutes: "Every 15 minutes"
        case .thirtyMinutes: "Every 30 minutes"
        }
    }
}

/// Build metadata for the About pane. A real version arrives with M6
/// packaging; until then the commit-distance placeholder is honest.
public enum LinuxAppInfo {
    public static let version = "0.1.0-dev"
}
