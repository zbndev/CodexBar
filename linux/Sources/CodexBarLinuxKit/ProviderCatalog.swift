import CodexBarCore
import Foundation

/// Decides which providers to show, and produces their pre-fetch appearance.
public enum ProviderCatalog {
    /// Providers to display. With no config file, falls back to the
    /// descriptors that opt into being enabled by default — matching what a
    /// fresh CodexBar install shows.
    public static func enabledProviders(config: CodexBarConfig?) -> [ProviderDescriptor] {
        let all = ProviderDescriptorRegistry.all
        guard let config else {
            return all.filter { $0.metadata.defaultEnabled }
        }
        let overrides = Dictionary(
            config.providers.map { ($0.id, $0.enabled) },
            uniquingKeysWith: { _, last in last })
        return all.filter { descriptor in
            if let override = overrides[descriptor.id], let enabled = override {
                return enabled
            }
            return descriptor.metadata.defaultEnabled
        }
    }

    /// The card shown before any data has arrived.
    public static func placeholderView(
        for descriptor: ProviderDescriptor,
        enabled: Bool) -> ProviderView
    {
        ProviderView(
            id: descriptor.id.rawValue,
            displayName: descriptor.metadata.displayName,
            iconResourceName: descriptor.branding.iconResourceName,
            iconSVG: ProviderIcons.svg(named: descriptor.branding.iconResourceName),
            accentColorHex: descriptor.branding.color.hexString,
            enabled: enabled,
            isLoading: true,
            dashboardURL: descriptor.metadata.dashboardURL,
            statusPageURL: descriptor.metadata.statusPageURL,
            changelogURL: descriptor.metadata.changelogURL)
    }
}
