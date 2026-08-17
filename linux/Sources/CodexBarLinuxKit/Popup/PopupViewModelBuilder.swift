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

        let resolved = self.resolveSelection(selectedID, in: payload.providers)
        let selected = payload.providers.first { $0.id == resolved }

        return PopupViewModel(
            strip: strip,
            selectedID: resolved,
            detail: selected.map {
                self.detail(
                    for: $0,
                    settings: settings,
                    strings: payload.localization.strings,
                    now: now)
            })
    }

    // MARK: - Detail

    /// `app.js`'s `renderDetail`, minus the DOM. The sessions list and the cost
    /// block are deliberately absent: they sit under every body state rather
    /// than inside one, and they arrive in Task 7.
    private static func detail(
        for provider: ProviderView,
        settings: LinuxSettings,
        strings: [String: String],
        now: Date) -> DetailViewModel
    {
        DetailViewModel(
            title: provider.displayName,
            freshness: provider.isLoading
                ? self.template("Updating…", fallback: "Updating…", strings)
                : self.freshness(updatedAt: provider.updatedAt, now: now),
            plan: settings.hidePersonalInfo ? "" : (provider.plan ?? ""),
            isUnavailable: provider.operationalStatus == .unavailable,
            body: self.body(for: provider, settings: settings, strings: strings, now: now),
            changelogURL: provider.changelogURL)
    }

    /// `renderProviderBody`'s ladder. The order is the order of its early
    /// returns and is load-bearing: a provider can be refreshing *and* holding
    /// the error from its last attempt, and the error is the more useful of
    /// the two.
    private static func body(
        for provider: ProviderView,
        settings: LinuxSettings,
        strings: [String: String],
        now: Date) -> DetailBody
    {
        if let error = provider.errorMessage, !error.isEmpty { return .message(error) }
        if provider.isLoading, provider.windows.isEmpty {
            return .message(self.template("linux.settings.loading", fallback: "Loading…", strings))
        }
        if provider.windows.isEmpty {
            return .message(self.template(
                "No usage windows reported.", fallback: "No usage windows reported.", strings))
        }

        return .usage(provider.windows.map { window in
            UsageRow(
                id: window.id,
                title: window.title,
                gauge: self.gauge(
                    percent: window.usedPercent, showUsed: settings.usageBarsShowUsed) ?? 0,
                percentText: self.percentText(
                    usedPercent: window.usedPercent,
                    showUsed: settings.usageBarsShowUsed,
                    strings: strings),
                resetText: ResetFormatting.line(
                    for: window,
                    now: now,
                    showAbsolute: settings.resetTimesShowAbsolute,
                    strings: strings))
        })
    }

    // MARK: - Freshness

    /// Second-level precision is noise in a window that refreshes once a
    /// minute, so the line stays relative until relative stops being
    /// informative.
    ///
    /// English literals, like the `Updated ${…}` of `app.js:135-145` they
    /// replace: the catalogs come from upstream and there is no key for this
    /// line, so a lookup would only ever return the text below.
    public static func freshness(updatedAt: Date?, now: Date) -> String {
        guard let updatedAt else { return "" }
        let elapsed = now.timeIntervalSince(updatedAt)
        if elapsed < 45 { return "Updated just now" }
        let minutes = Int((elapsed / 60).rounded())
        if minutes < 90 { return "Updated \(minutes) min ago" }
        return "Updated \(self.clockFormatter().string(from: updatedAt))"
    }

    private static func clockFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
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

    /// The label beside the bar, mirroring `UsageFormatter.percentText` rather
    /// than the web version.
    ///
    /// Two deliberate differences from `app.js:302-306`. It clamps, so a
    /// provider reporting 140% does not print "140% used" next to a bar that
    /// can only sit at 100 — and with the remaining preference does not print
    /// "-40%" at all. And the suffixes are the upstream keys, so they translate:
    /// `t('remaining')` had no key and no alias and stayed English everywhere.
    static func percentText(
        usedPercent: Double,
        showUsed: Bool,
        strings: [String: String]) -> String
    {
        let displayed = showUsed ? usedPercent : 100 - usedPercent
        let clamped = min(100, max(0, displayed))
        let suffix = showUsed
            ? self.template("usage_percent_suffix_used", fallback: "used", strings)
            : self.template("usage_percent_suffix_left", fallback: "left", strings)

        // Rounding a non-zero sliver to "0% used" claims an untouched window.
        if clamped > 0, clamped < 1 {
            return String(
                format: self.template("<1%% %@", fallback: "<1%% %@", strings),
                locale: Locale.current,
                suffix)
        }
        return String(
            format: self.template("%.0f%% %@", fallback: "%.0f%% %@", strings),
            locale: Locale.current,
            clamped,
            suffix)
    }

    // MARK: - Wording

    /// The snapshot's catalog, with the English text as the fallback.
    ///
    /// A fallback rather than the key itself, unlike `ResetFormatting`: the two
    /// suffix keys are semantic upstream, so an absent catalog would otherwise
    /// render "73% usage_percent_suffix_used". The format keys are their own
    /// text and only zh-Hant overrides them — to put the suffix first, which is
    /// why they go through `String(format:)` and not string interpolation.
    private static func template(
        _ key: String,
        fallback: String,
        _ strings: [String: String]) -> String
    {
        strings[key] ?? fallback
    }
}
