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

private func payload(_ providers: [ProviderView]) -> ProviderSnapshotPayload {
    ProviderSnapshotPayload(
        generatedAt: Date(timeIntervalSince1970: 0), providers: providers)
}

private func model(
    _ providers: [ProviderView],
    settings: LinuxSettings = LinuxSettings(),
    selectedID: String? = nil) -> PopupViewModel
{
    PopupViewModelBuilder.make(
        payload: payload(providers),
        settings: settings,
        selectedID: selectedID,
        now: Date(timeIntervalSince1970: 0))
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
