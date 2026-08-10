import CodexBarCore
import Foundation

/// Builds the `ProviderSettingsSnapshot` a fetch context carries, from the
/// config file the Linux GUI persists.
///
/// On macOS this snapshot is assembled by each provider implementation from
/// its `SettingsStore`; none of that layer exists here, and a context built
/// without it leaves every cookie strategy blind — `isAvailable` returns false
/// and the pipeline fails the provider with `noAvailableStrategy`.
///
/// Sections come from each descriptor's own
/// `settingsSection.credentialContribution`, the seam `TokenAccountCLI` uses to
/// build a snapshot with no `SettingsStore` behind it. Coverage therefore
/// follows upstream's registrations, and there is no provider list to maintain
/// here — only the descriptors that register no credential reader at all.
public enum LinuxSettingsSnapshot {
    public static func make(config: CodexBarConfig?) -> ProviderSettingsSnapshot {
        var builder = ProviderSettingsSnapshotBuilder()
        for descriptor in ProviderDescriptorRegistry.all {
            guard let stored = config?.providerConfig(for: descriptor.id.instanceID) else { continue }
            let context = ProviderCredentialSettingsContext(
                config: stored,
                account: UsageRefresher.activeTokenAccount(stored))
            let contribution = descriptor.settingsSection.credentialContribution(context: context)
                ?? self.unregisteredContribution(descriptor: descriptor, config: stored)
            guard let contribution else { continue }
            builder.apply(contribution)
        }
        return builder.build()
    }

    /// Sections for providers whose descriptor registers no credential reader.
    /// Upstream fills these from a `SettingsStore` that has no counterpart
    /// here, so the stored config fields are mapped directly instead.
    private static func unregisteredContribution(
        descriptor: ProviderDescriptor,
        config: ProviderConfig) -> ProviderSettingsSnapshotContribution?
    {
        switch descriptor.id {
        case .devin:
            // Devin's manual credential is an Authorization header value.
            ProviderSettingsSnapshotContribution.devin(ProviderSettingsSnapshot.DevinProviderSettings(
                cookieSource: config.cookieSource ?? .auto,
                manualBearerToken: config.sanitizedCookieHeader,
                organization: config.sanitizedWorkspaceID))
        default:
            nil
        }
    }

    /// The manual cookie header the snapshot carries for `provider`, or nil
    /// when the provider contributes none. The inverse of `make`, read back
    /// through the same registration that wrote the section.
    public static func cookieHeader(
        in snapshot: ProviderSettingsSnapshot,
        for provider: UsageProvider) -> String?
    {
        // Devin registers no cookie reader because its credential is a bearer
        // token, so the section written above has to be read back directly.
        if provider == .devin {
            return snapshot.devin?.manualBearerToken
        }
        return ProviderDescriptorRegistry.descriptor(for: provider)
            .settingsSection
            .cookieSettings(from: snapshot)?
            .manualCookieHeader
    }
}
