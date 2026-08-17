import Foundation
import Testing

@testable import CodexBarLinuxKit

private func provider(
    id: String,
    windows: [ProviderWindowView] = []) -> ProviderView
{
    ProviderView(
        id: id,
        displayName: id.capitalized,
        iconResourceName: "ProviderIcon-\(id)",
        accentColorHex: "#112233",
        enabled: true,
        windows: windows)
}

private func window(_ used: Double) -> ProviderWindowView {
    ProviderWindowView(id: "w\(used)", title: "W", usedPercent: used)
}

/// An empty catalog rather than the loaded one: every key the builder looks up
/// carries an explicit English fallback, so this keeps the assertions readable
/// and independent of both `Locale.current` and the resource directory.
private func payload(_ providers: [ProviderView]) -> ProviderSnapshotPayload {
    ProviderSnapshotPayload(
        generatedAt: Date(timeIntervalSince1970: 0),
        providers: providers,
        localization: LocalizationPayload(locale: "en", strings: [:], plurals: [:]))
}

private func model(
    _ providers: [ProviderView],
    settings: LinuxSettings = LinuxSettings(),
    selectedID: String? = nil,
    now: Date = Date(timeIntervalSince1970: 0)) -> PopupViewModel
{
    PopupViewModelBuilder.make(
        payload: payload(providers),
        settings: settings,
        selectedID: selectedID,
        now: now)
}

@Test func `the strip gauge reports the most used window`() {
    let result = model([provider(id: "claude", windows: [window(12), window(73), window(40)])])
    #expect(result.strip.first?.gauge == 0.73)
}

@Test func `a provider with no windows has no gauge rather than a zero one`() {
    let result = model([provider(id: "kimi")])
    #expect(result.strip.first?.gauge == nil)
}

@Test func `the remaining preference inverts the gauge`() {
    var settings = LinuxSettings()
    settings.usageBarsShowUsed = false
    let result = model([provider(id: "codex", windows: [window(70)])], settings: settings)
    #expect(result.strip.first?.gauge == 0.30)
}

@Test func `an out of range percentage is clamped to the track`() {
    #expect(model([provider(id: "amp", windows: [window(140)])]).strip.first?.gauge == 1.0)
    #expect(model([provider(id: "amp", windows: [window(-40)])]).strip.first?.gauge == 0.0)
}

@Test func `the strip keeps the payload's order rather than sorting it`() {
    let result = model([provider(id: "zed"), provider(id: "amp"), provider(id: "claude")])
    #expect(result.strip.map(\.id) == ["zed", "amp", "claude"])
}

@Test func `nothing selected falls back to the first provider`() {
    // `app.js:31-32`: a snapshot arriving with no selection selects the head of
    // the list, so the popup is never showing a strip with no detail under it.
    #expect(model([provider(id: "zed"), provider(id: "amp")]).selectedID == "zed")
    #expect(model([]).selectedID == nil)
}

@Test func `a selection that no longer exists falls back rather than sticking`() {
    // A provider can be disabled between snapshots; `app.js:45` resolves the id
    // against the list every render and yields null when it misses.
    let result = model([provider(id: "amp")], selectedID: "claude")
    #expect(result.selectedID == "amp")
}

// MARK: - Detail header

@Test func `freshness stays relative until relative stops being informative`() {
    let now = Date(timeIntervalSince1970: 10_000)
    #expect(PopupViewModelBuilder.freshness(updatedAt: now.addingTimeInterval(-10), now: now)
        == "Updated just now")
    #expect(PopupViewModelBuilder.freshness(updatedAt: now.addingTimeInterval(-600), now: now)
        == "Updated 10 min ago")
    // Past 90 minutes it becomes a clock time, so only the prefix is asserted.
    let old = PopupViewModelBuilder.freshness(updatedAt: now.addingTimeInterval(-7200), now: now)
    #expect(old.hasPrefix("Updated "))
    #expect(!old.hasSuffix("min ago"))
    #expect(PopupViewModelBuilder.freshness(updatedAt: nil, now: now).isEmpty)
}

@Test func `a loading provider says so instead of dating its last snapshot`() {
    // `app.js:210-214`: the freshness slot is the only sign of a refresh in
    // flight once a provider already has windows, since the body keeps showing
    // them rather than falling back to the loading message.
    var view = provider(id: "claude", windows: [window(20)])
    view.isLoading = true
    view.updatedAt = Date(timeIntervalSince1970: -600)
    let detail = model([view], selectedID: "claude").detail
    #expect(detail?.freshness == "Updating…")
    #expect(detail?.body == .usage([
        UsageRow(id: "w20.0", title: "W", gauge: 0.2, percentText: "20% used", resetText: ""),
    ]))
}

@Test func `hiding personal info empties the plan line`() {
    var settings = LinuxSettings()
    settings.hidePersonalInfo = true
    var view = provider(id: "claude", windows: [window(20)])
    view.plan = "Max 20x"
    #expect(model([view], settings: settings, selectedID: "claude").detail?.plan.isEmpty == true)
    #expect(model([view], selectedID: "claude").detail?.plan == "Max 20x")
}

@Test func `an unavailable service is flagged beside the body, not instead of it`() {
    // `app.js:281-287` appends the banner and carries on, so the usage rows
    // stay visible under it. A `DetailBody` case would have replaced them.
    var view = provider(id: "codex", windows: [window(20)])
    view.operationalStatus = .unavailable
    let detail = model([view], selectedID: "codex").detail
    #expect(detail?.isUnavailable == true)
    #expect(detail?.body == .usage([
        UsageRow(id: "w20.0", title: "W", gauge: 0.2, percentText: "20% used", resetText: ""),
    ]))
}

@Test func `the changelog link rides along when the provider has one`() {
    var view = provider(id: "codex", windows: [window(20)])
    view.changelogURL = "https://example.invalid/changelog"
    #expect(model([view], selectedID: "codex").detail?.changelogURL
        == "https://example.invalid/changelog")
    #expect(model([provider(id: "codex")], selectedID: "codex").detail?.changelogURL == nil)
}

// MARK: - Detail body

@Test func `an error message replaces the usage rows rather than joining them`() {
    var view = provider(id: "codex", windows: [window(20)])
    view.errorMessage = "No available strategy"
    #expect(model([view], selectedID: "codex").detail?.body == .message("No available strategy"))
}

@Test func `loading with nothing to show yet is a message, not an empty list`() {
    var view = provider(id: "codex")
    view.isLoading = true
    #expect(model([view], selectedID: "codex").detail?.body == .message("Loading…"))
}

@Test func `a provider that reports no windows says so`() {
    #expect(model([provider(id: "codex")], selectedID: "codex").detail?.body
        == .message("No usage windows reported."))
}

@Test func `an error outranks loading, which outranks the empty list`() {
    // The three states are mutually exclusive in `app.js:289-311` because each
    // returns; ported as a ladder, the order has to be pinned or a loading
    // provider with a stale error would silently hide the error.
    var view = provider(id: "codex")
    view.isLoading = true
    view.errorMessage = "boom"
    #expect(model([view], selectedID: "codex").detail?.body == .message("boom"))
}

@Test func `selecting nothing with no providers yields an empty state`() {
    #expect(model([]).detail == nil)
}

// MARK: - Usage rows

@Test func `a usage row carries the same preference as its gauge`() {
    var settings = LinuxSettings()
    settings.usageBarsShowUsed = false
    let rows = model([provider(id: "codex", windows: [window(70)])], settings: settings)
        .detail?.body
    #expect(rows == .usage([
        UsageRow(id: "w70.0", title: "W", gauge: 0.30, percentText: "30% left", resetText: ""),
    ]))
}

@Test func `a percentage over the window is clamped in the text as well as the bar`() {
    // `UsageFormatter.percentText` clamps; `app.js:305` rounded the raw value,
    // so the web bar sat full while its label read "140% used" — and with the
    // remaining preference the same line read "-40% remaining".
    let over = model([provider(id: "codex", windows: [window(140)])]).detail?.body
    #expect(over == .usage([
        UsageRow(id: "w140.0", title: "W", gauge: 1.0, percentText: "100% used", resetText: ""),
    ]))
}

@Test func `a sliver of usage reads as under one percent rather than none`() {
    // The `<1%` rule is upstream's, in `UsageFormatter.percentText`: rounding
    // 0.4% to "0% used" claims a window is untouched when it is not.
    let sliver = model([provider(id: "codex", windows: [window(0.4)])]).detail?.body
    #expect(sliver == .usage([
        UsageRow(id: "w0.4", title: "W", gauge: 0.004, percentText: "<1% used", resetText: ""),
    ]))
    let none = model([provider(id: "codex", windows: [window(0)])]).detail?.body
    #expect(none == .usage([
        UsageRow(id: "w0.0", title: "W", gauge: 0.0, percentText: "0% used", resetText: ""),
    ]))
}

@Test func `the reset line follows the reset time preference`() {
    let now = Date(timeIntervalSince1970: 0)
    var slot = window(20)
    slot.resetsAt = now.addingTimeInterval(3600)
    let relative = model([provider(id: "codex", windows: [slot])], now: now).detail?.body
    #expect(relative == .usage([
        UsageRow(
            id: "w20.0",
            title: "W",
            gauge: 0.2,
            percentText: "20% used",
            resetText: "Resets in 1h"),
    ]))

    var settings = LinuxSettings()
    settings.resetTimesShowAbsolute = true
    let absolute = model(
        [provider(id: "codex", windows: [slot])], settings: settings, now: now).detail?.body
    guard case let .usage(rows) = absolute else { Issue.record("expected usage rows"); return }
    // The clock string is locale- and zone-dependent, so only its shape is
    // asserted — `ResetFormattingTests` pins the wording itself.
    #expect(rows.first?.resetText.hasPrefix("Resets ") == true)
    #expect(rows.first?.resetText.contains("in 1h") == false)
}

@Test func `the localisation catalog reaches the usage line`() {
    // The suffixes are real upstream keys, unlike `app.js`'s `t('remaining')`,
    // which had no key and no alias and so stayed English in every locale.
    let translated = ProviderSnapshotPayload(
        generatedAt: Date(timeIntervalSince1970: 0),
        providers: [provider(id: "codex", windows: [window(20)])],
        localization: LocalizationPayload(
            locale: "ru",
            strings: ["usage_percent_suffix_used": "использовано"],
            plurals: [:]))
    let result = PopupViewModelBuilder.make(
        payload: translated,
        settings: LinuxSettings(),
        selectedID: "codex",
        now: Date(timeIntervalSince1970: 0))
    guard case let .usage(rows) = result.detail?.body else {
        Issue.record("expected usage rows")
        return
    }
    #expect(rows.first?.percentText == "20% использовано")
}
