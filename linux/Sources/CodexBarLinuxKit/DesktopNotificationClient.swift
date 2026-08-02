import CGtk4
import Foundation

public protocol DesktopNotificationSending: Sendable {
    func send(summary: String, body: String, urgency: UInt8, sound: Bool) async throws
}

public enum DesktopNotificationUrgency: UInt8, Sendable {
    case low = 0
    case normal = 1
    case critical = 2
}

public struct DesktopNotificationRequest: Equatable, Sendable {
    public let service: String
    public let objectPath: String
    public let method: String
    public let appName: String
    public let summary: String
    public let body: String
    public let transient: Bool
    public let urgency: UInt8
    public let suppressSound: Bool
    public let timeoutMilliseconds: Int

    public init(
        service: String,
        objectPath: String,
        method: String,
        appName: String,
        summary: String,
        body: String,
        transient: Bool,
        urgency: UInt8,
        suppressSound: Bool,
        timeoutMilliseconds: Int)
    {
        self.service = service
        self.objectPath = objectPath
        self.method = method
        self.appName = appName
        self.summary = summary
        self.body = body
        self.transient = transient
        self.urgency = urgency
        self.suppressSound = suppressSound
        self.timeoutMilliseconds = timeoutMilliseconds
    }
}

public protocol GDBusNotificationCalling: Sendable {
    func call(_ request: DesktopNotificationRequest) async throws
}

public enum DesktopNotificationError: Error, Sendable {
    case serviceUnavailable
}

public struct DesktopNotificationClient: DesktopNotificationSending {
    private let bus: any GDBusNotificationCalling

    public init() {
        self.bus = GDBusNotificationCaller()
    }

    public init(bus: any GDBusNotificationCalling) {
        self.bus = bus
    }

    public func send(summary: String, body: String, urgency: UInt8, sound: Bool) async throws {
        try await self.bus.call(DesktopNotificationRequest(
            service: "org.freedesktop.Notifications",
            objectPath: "/org/freedesktop/Notifications",
            method: "Notify",
            appName: "CodexBar",
            summary: summary,
            body: body,
            transient: true,
            urgency: urgency,
            suppressSound: !sound,
            timeoutMilliseconds: 8_000))
    }
}

private struct GDBusNotificationCaller: GDBusNotificationCalling {
    func call(_ request: DesktopNotificationRequest) async throws {
        let sent = codexbar_send_desktop_notification(
            request.summary,
            request.body,
            request.urgency,
            request.suppressSound ? 1 : 0)
        guard sent != 0 else { throw DesktopNotificationError.serviceUnavailable }
    }
}
