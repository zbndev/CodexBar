import Foundation
import Testing

@testable import CodexBarLinuxKit

private actor DesktopNotificationCallRecorder {
    private var calls: [DesktopNotificationRequest] = []

    func append(_ call: DesktopNotificationRequest) {
        self.calls.append(call)
    }

    func first() -> DesktopNotificationRequest? {
        self.calls.first
    }
}

private struct FakeGDBusNotificationCaller: GDBusNotificationCalling {
    let recorder: DesktopNotificationCallRecorder

    func call(_ request: DesktopNotificationRequest) async throws {
        await self.recorder.append(request)
    }
}

@Test func `desktop notifications use the freedesktop Notify payload without account identity`() async throws {
    let recorder = DesktopNotificationCallRecorder()
    let client = DesktopNotificationClient(bus: FakeGDBusNotificationCaller(recorder: recorder))

    try await client.send(
        summary: "Quota warning",
        body: "Claude / primary / 19% remaining",
        urgency: DesktopNotificationUrgency.normal.rawValue,
        sound: true)

    let request = try #require(await recorder.first())
    #expect(request.service == "org.freedesktop.Notifications")
    #expect(request.objectPath == "/org/freedesktop/Notifications")
    #expect(request.method == "Notify")
    #expect(request.appName == "CodexBar")
    #expect(request.transient)
    #expect(request.urgency == DesktopNotificationUrgency.normal.rawValue)
    #expect(!request.suppressSound)
    #expect(request.timeoutMilliseconds == 8_000)
    #expect(request.body == "Claude / primary / 19% remaining")
    #expect(!request.body.contains("account"))
}

@Test func `sound preference changes only the desktop notification hint`() async throws {
    let recorder = DesktopNotificationCallRecorder()
    let client = DesktopNotificationClient(bus: FakeGDBusNotificationCaller(recorder: recorder))

    try await client.send(summary: "Quota warning", body: "Claude / primary / 19% remaining", urgency: 1, sound: false)

    let request = try #require(await recorder.first())
    #expect(request.suppressSound)
}
