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

/// One usage window in the detail pane.
///
/// `gauge` and `percentText` are derived from the same number through the same
/// preference, so the bar and its label cannot drift apart.
public struct UsageRow: Equatable, Sendable {
    public var id: String
    public var title: String
    /// 0…1, for `GtkLevelBar`.
    public var gauge: Double
    /// "73% used" / "27% left", already localised and clamped.
    public var percentText: String
    /// "" when the provider says nothing about the reset.
    public var resetText: String

    public init(
        id: String,
        title: String,
        gauge: Double,
        percentText: String,
        resetText: String)
    {
        self.id = id
        self.title = title
        self.gauge = gauge
        self.percentText = percentText
        self.resetText = resetText
    }
}

/// What sits between the detail header and the sessions list.
///
/// The four early returns of `app.js`'s `renderProviderBody` collapse to two
/// cases: usage rows, or the single line that stands in for them. The
/// unavailable banner is not here — it renders *above* the body rather than
/// instead of it, so it travels as `DetailViewModel.isUnavailable`.
public enum DetailBody: Equatable, Sendable {
    case usage([UsageRow])
    /// An error, "Loading…", or "No usage windows reported.".
    case message(String)
}

/// The selected provider's pane.
public struct DetailViewModel: Equatable, Sendable {
    public var title: String
    /// "Updated just now", "Updating…" while a refresh is in flight, or "".
    public var freshness: String
    /// "" when `hidePersonalInfo` is on, or when the provider reports no plan.
    public var plan: String
    /// `operationalStatus == .unavailable`; renders as a banner over the body.
    public var isUnavailable: Bool
    public var body: DetailBody
    public var changelogURL: String?

    public init(
        title: String,
        freshness: String,
        plan: String,
        isUnavailable: Bool,
        body: DetailBody,
        changelogURL: String? = nil)
    {
        self.title = title
        self.freshness = freshness
        self.plan = plan
        self.isUnavailable = isUnavailable
        self.body = body
        self.changelogURL = changelogURL
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
    /// Nil when no provider is selected, which is only ever the case when none
    /// is enabled. The renderer draws its own "No providers enabled." there;
    /// the model has nothing to say about a provider that does not exist.
    public var detail: DetailViewModel?

    public init(
        strip: [StripItem] = [],
        selectedID: String? = nil,
        detail: DetailViewModel? = nil)
    {
        self.strip = strip
        self.selectedID = selectedID
        self.detail = detail
    }
}
