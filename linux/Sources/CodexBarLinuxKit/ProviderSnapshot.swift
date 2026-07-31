import CodexBarCore
import Foundation

extension ProviderColor {
    /// `#RRGGBB`, for handing straight to CSS.
    public var hexString: String {
        func channel(_ value: Double) -> Int {
            Int((value * 255).rounded()).clamped(to: 0...255)
        }
        return String(format: "#%02X%02X%02X", channel(self.red), channel(self.green), channel(self.blue))
    }
}

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// One usage window as the UI needs it.
public struct ProviderWindowView: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var resetDescription: String?

    public init(
        id: String,
        title: String,
        usedPercent: Double,
        resetsAt: Date? = nil,
        resetDescription: String? = nil)
    {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }
}

/// One provider card.
public struct ProviderView: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var iconResourceName: String
    public var iconSVG: String?
    public var accentColorHex: String
    public var enabled: Bool
    public var windows: [ProviderWindowView]
    public var plan: String?
    public var accountEmail: String?
    public var updatedAt: Date?
    public var sourceLabel: String?
    public var errorMessage: String?
    public var isLoading: Bool
    public var dashboardURL: String?
    public var statusPageURL: String?

    public init(
        id: String,
        displayName: String,
        iconResourceName: String,
        iconSVG: String? = nil,
        accentColorHex: String,
        enabled: Bool,
        windows: [ProviderWindowView] = [],
        plan: String? = nil,
        accountEmail: String? = nil,
        updatedAt: Date? = nil,
        sourceLabel: String? = nil,
        errorMessage: String? = nil,
        isLoading: Bool = false,
        dashboardURL: String? = nil,
        statusPageURL: String? = nil)
    {
        self.id = id
        self.displayName = displayName
        self.iconResourceName = iconResourceName
        self.iconSVG = iconSVG
        self.accentColorHex = accentColorHex
        self.enabled = enabled
        self.windows = windows
        self.plan = plan
        self.accountEmail = accountEmail
        self.updatedAt = updatedAt
        self.sourceLabel = sourceLabel
        self.errorMessage = errorMessage
        self.isLoading = isLoading
        self.dashboardURL = dashboardURL
        self.statusPageURL = statusPageURL
    }
}

/// The whole UI state in one message.
public struct ProviderSnapshotPayload: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var providers: [ProviderView]

    public init(generatedAt: Date, providers: [ProviderView]) {
        self.generatedAt = generatedAt
        self.providers = providers
    }
}
