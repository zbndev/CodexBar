import Foundation

/// One provider in the popup's top strip.
///
/// `brandHex` paints the gauge and nothing else. Selection is left to the
/// system accent: six of the shipped brand colours sit near `#211E1E`, so a
/// brand-coloured highlight is unreadable on the dark theme — the same reason
/// `app.js:157-159` set `--brand` on the bar but not on the tab.
public struct StripItem: Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var iconSVG: String?
    public var brandHex: String
    /// 0…1, already through the used/remaining preference. Nil renders an empty track.
    public var gauge: Double?

    public init(
        id: String,
        displayName: String,
        iconSVG: String? = nil,
        brandHex: String,
        gauge: Double? = nil)
    {
        self.id = id
        self.displayName = displayName
        self.iconSVG = iconSVG
        self.brandHex = brandHex
        self.gauge = gauge
    }
}

/// Everything the popup shows, as a value the renderer can diff.
///
/// The renderer holds one of these and updates widget properties in place; it
/// makes no decisions of its own, which is what keeps the 523 lines of display
/// logic that used to live in `app.js` under ordinary unit tests.
public struct PopupViewModel: Equatable, Sendable {
    public var strip: [StripItem]
    /// Always an id present in `strip`, or nil when there is nothing to select.
    public var selectedID: String?

    public init(strip: [StripItem] = [], selectedID: String? = nil) {
        self.strip = strip
        self.selectedID = selectedID
    }
}
