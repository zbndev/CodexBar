import Foundation

/// Turns a snapshot into the value the popup renderer draws.
///
/// This is the whole testing boundary for the native popup: a pure function
/// from `ProviderSnapshotPayload` to `PopupViewModel`, tested the way
/// `SnapshotBuilder` already is, with no GTK anywhere near it.
///
/// `settings` is passed in rather than read from `payload.display` because the
/// caller is the only place that knows which settings the payload was built
/// from; the two must be the same object, and `main.swift` passes it straight
/// through. `now` is a parameter for the reason `ResetFormatting` takes one —
/// every relative wording downstream turns on it.
public enum PopupViewModelBuilder {
    public static func make(
        payload: ProviderSnapshotPayload,
        settings: LinuxSettings,
        selectedID: String?,
        now: Date) -> PopupViewModel
    {
        let strip = payload.providers.map { provider in
            StripItem(
                id: provider.id,
                displayName: provider.displayName,
                iconSVG: provider.iconSVG,
                brandHex: provider.accentColorHex,
                gauge: self.gauge(
                    percent: self.highestUsedPercent(provider),
                    showUsed: settings.usageBarsShowUsed))
        }

        return PopupViewModel(
            strip: strip,
            selectedID: self.resolveSelection(selectedID, in: payload.providers))
    }

    // MARK: - Selection

    /// A snapshot with no selection selects the head of the list, and a
    /// selection naming a provider that has since been disabled falls back the
    /// same way. Both rules are `app.js:31-32` and `app.js:45`; keeping them
    /// here means the renderer never has to hold a selection the strip cannot
    /// show.
    private static func resolveSelection(
        _ selectedID: String?,
        in providers: [ProviderView]) -> String?
    {
        if let selectedID, providers.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return providers.first?.id
    }

    // MARK: - Gauges

    /// The provider's most-used window, which is what its strip bar reports.
    /// Nil while nothing has loaded, so the bar renders as an empty track
    /// rather than a full-looking zero.
    private static func highestUsedPercent(_ provider: ProviderView) -> Double? {
        provider.windows.map(\.usedPercent).max()
    }

    /// Bars can show used or remaining; the strip gauge and the detail bars
    /// must never disagree, so both go through here.
    ///
    /// The result is a 0…1 fraction rather than a percent because that is what
    /// `GtkLevelBar` wants, and doing the division once here keeps arithmetic
    /// out of the renderer entirely.
    static func gauge(percent: Double?, showUsed: Bool) -> Double? {
        guard let percent else { return nil }
        let displayed = showUsed ? percent : 100 - percent
        return min(100, max(0, displayed)) / 100
    }
}
