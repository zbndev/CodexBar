import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

/// `RateWindow.init` takes `resetDescription` with no default, and
/// `UsageSnapshot.init` takes `updatedAt` with no default. These wrap both so
/// the tests below read as intent rather than as argument lists.
private func makeWindow(usedPercent: Double, windowMinutes: Int) -> RateWindow {
    RateWindow(
        usedPercent: usedPercent,
        windowMinutes: windowMinutes,
        resetsAt: nil,
        resetDescription: nil)
}

private func makeUsage(primary: RateWindow?, secondary: RateWindow?) -> UsageSnapshot {
    UsageSnapshot(
        primary: primary,
        secondary: secondary,
        updatedAt: Date(timeIntervalSince1970: 0))
}

@Test func `a primary window becomes the session card row`() {
    let descriptor = ProviderDescriptorRegistry.descriptor(for: .claude)
    let usage = makeUsage(
        primary: makeWindow(usedPercent: 42, windowMinutes: 300),
        secondary: nil)
    let view = SnapshotBuilder.view(
        descriptor: descriptor,
        enabled: true,
        usage: usage,
        sourceLabel: "oauth")

    #expect(view.windows.count == 1)
    #expect(view.windows[0].id == "primary")
    #expect(view.windows[0].title == descriptor.metadata.sessionLabel)
    #expect(view.windows[0].usedPercent == 42)
    #expect(!view.isLoading)
    #expect(view.sourceLabel == "oauth")
}

@Test func `primary and secondary windows both appear in order`() {
    let descriptor = ProviderDescriptorRegistry.descriptor(for: .claude)
    let usage = makeUsage(
        primary: makeWindow(usedPercent: 10, windowMinutes: 300),
        secondary: makeWindow(usedPercent: 60, windowMinutes: 10_080))
    let view = SnapshotBuilder.view(
        descriptor: descriptor,
        enabled: true,
        usage: usage,
        sourceLabel: "oauth")

    #expect(view.windows.map(\.id) == ["primary", "secondary"])
    #expect(view.windows[1].title == descriptor.metadata.weeklyLabel)
    #expect(view.windows[1].usedPercent == 60)
}

@Test func `a provider with no windows produces an empty window list rather than a crash`() {
    let descriptor = ProviderDescriptorRegistry.descriptor(for: .claude)
    let view = SnapshotBuilder.view(
        descriptor: descriptor,
        enabled: true,
        usage: makeUsage(primary: nil, secondary: nil),
        sourceLabel: "api")
    #expect(view.windows.isEmpty)
}

@Test func `named extra windows keep their own titles`() {
    let descriptor = ProviderDescriptorRegistry.descriptor(for: .claude)
    let usage = UsageSnapshot(
        primary: nil,
        secondary: nil,
        extraRateWindows: [
            NamedRateWindow(
                id: "credits",
                title: "Credits",
                window: makeWindow(usedPercent: 25, windowMinutes: 43_200)),
        ],
        updatedAt: Date(timeIntervalSince1970: 0))
    let view = SnapshotBuilder.view(
        descriptor: descriptor,
        enabled: true,
        usage: usage,
        sourceLabel: "api")

    #expect(view.windows.map(\.id) == ["credits"])
    #expect(view.windows[0].title == "Credits")
}

private struct SampleError: Error {}

@Test func `a failed fetch produces a card carrying the error`() {
    let descriptor = ProviderDescriptorRegistry.descriptor(for: .codex)
    let view = SnapshotBuilder.failureView(
        descriptor: descriptor,
        enabled: true,
        error: SampleError())
    #expect(view.errorMessage != nil)
    #expect(!view.isLoading)
    #expect(view.windows.isEmpty)
    #expect(view.displayName == descriptor.metadata.displayName)
}

@Test func `brand icons resolve from the root package resources`() {
    let descriptor = ProviderDescriptorRegistry.descriptor(for: .claude)
    let svg = ProviderIcons.svg(named: descriptor.branding.iconResourceName)
    #expect(svg != nil)
    #expect(svg?.contains("<svg") == true)
}
