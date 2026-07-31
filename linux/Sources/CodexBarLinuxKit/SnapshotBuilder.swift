import CodexBarCore
import Foundation

/// Turns a Core `UsageSnapshot` into the card the UI renders.
///
/// Window titles come from the descriptor, so a provider added upstream is
/// labelled correctly without any code here changing.
public enum SnapshotBuilder {
    public static func view(
        descriptor: ProviderDescriptor,
        enabled: Bool,
        usage: UsageSnapshot,
        sourceLabel: String) -> ProviderView
    {
        var windows: [ProviderWindowView] = []

        if let primary = usage.primary {
            windows.append(ProviderWindowView(
                id: "primary",
                title: descriptor.metadata.sessionLabel,
                usedPercent: primary.usedPercent,
                resetsAt: primary.resetsAt,
                resetDescription: primary.resetDescription))
        }
        if let secondary = usage.secondary {
            windows.append(ProviderWindowView(
                id: "secondary",
                title: descriptor.metadata.weeklyLabel,
                usedPercent: secondary.usedPercent,
                resetsAt: secondary.resetsAt,
                resetDescription: secondary.resetDescription))
        }
        if let tertiary = usage.tertiary {
            windows.append(ProviderWindowView(
                id: "tertiary",
                title: descriptor.metadata.opusLabel ?? "Extra",
                usedPercent: tertiary.usedPercent,
                resetsAt: tertiary.resetsAt,
                resetDescription: tertiary.resetDescription))
        }
        for named in usage.extraRateWindows ?? [] {
            windows.append(ProviderWindowView(
                id: named.id,
                title: named.title,
                usedPercent: named.window.usedPercent,
                resetsAt: named.window.resetsAt,
                resetDescription: named.window.resetDescription))
        }

        return ProviderView(
            id: descriptor.id.rawValue,
            displayName: descriptor.metadata.displayName,
            iconResourceName: descriptor.branding.iconResourceName,
            accentColorHex: descriptor.branding.color.hexString,
            enabled: enabled,
            windows: windows,
            plan: usage.identity?.loginMethod,
            accountEmail: usage.identity?.accountEmail,
            updatedAt: usage.updatedAt,
            sourceLabel: sourceLabel,
            errorMessage: nil,
            isLoading: false,
            dashboardURL: descriptor.metadata.dashboardURL,
            statusPageURL: descriptor.metadata.statusPageURL)
    }

    public static func failureView(
        descriptor: ProviderDescriptor,
        enabled: Bool,
        error: Error) -> ProviderView
    {
        ProviderView(
            id: descriptor.id.rawValue,
            displayName: descriptor.metadata.displayName,
            iconResourceName: descriptor.branding.iconResourceName,
            accentColorHex: descriptor.branding.color.hexString,
            enabled: enabled,
            windows: [],
            errorMessage: String(describing: error),
            isLoading: false,
            dashboardURL: descriptor.metadata.dashboardURL,
            statusPageURL: descriptor.metadata.statusPageURL)
    }
}
