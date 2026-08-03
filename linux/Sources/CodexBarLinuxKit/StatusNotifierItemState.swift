import Foundation

/// The properties of an `org.kde.StatusNotifierItem`, rendered as GVariant
/// text.
///
/// The property set is copied from the introspection XML inside
/// `libayatana-appindicator-glib.so.2`, the library this replaces, so every
/// host that worked against that library still finds what it reads. Anything
/// the library did not publish — `IconPixmap`, `ItemIsMenu` — is deliberately
/// absent: adding properties changes host behaviour and belongs in its own
/// change, not in a packaging milestone.
///
/// Pure data, so the whole property surface is testable without a bus.
public struct StatusNotifierItemState: Equatable, Sendable {
    public var id: String
    public var category: String
    public var status: String
    public var title: String
    public var iconName: String
    /// A directory searched ahead of the icon theme. Empty means "theme only",
    /// which is what an installed build wants — its icon is in hicolor.
    public var iconThemePath: String
    /// Text drawn next to the icon. Empty hides it.
    public var label: String
    /// A widest-case sample string hosts may use to reserve width.
    public var labelGuide: String
    public var menuPath: String
    public var orderingIndex: UInt32

    public init(
        id: String,
        category: String = "ApplicationStatus",
        status: String = "Active",
        title: String,
        iconName: String,
        iconThemePath: String = "",
        label: String = "",
        labelGuide: String = "",
        menuPath: String,
        orderingIndex: UInt32 = 0)
    {
        self.id = id
        self.category = category
        self.status = status
        self.title = title
        self.iconName = iconName
        self.iconThemePath = iconThemePath
        self.label = label
        self.labelGuide = labelGuide
        self.menuPath = menuPath
        self.orderingIndex = orderingIndex
    }

    /// In introspection order, so the test that walks them mirrors the XML.
    public static let propertyNames = [
        "Id", "Category", "Status", "IconName", "IconAccessibleDesc",
        "AttentionIconName", "AttentionAccessibleDesc", "Title",
        "IconThemePath", "Menu", "XAyatanaLabel", "XAyatanaLabelGuide",
        "XAyatanaOrderingIndex", "ToolTip",
    ]

    public func propertyType(for name: String) -> String? {
        switch name {
        case "Menu": "o"
        case "XAyatanaOrderingIndex": "u"
        case "ToolTip": "(sa(iiay)ss)"
        default: Self.propertyNames.contains(name) ? "s" : nil
        }
    }

    /// GVariant text for `name`, or nil when the interface does not declare it.
    ///
    /// Returning nil for a *declared* property would make a host drop the item,
    /// so the attention and accessibility properties answer with empty strings
    /// rather than nil — the library did the same.
    public func propertyText(for name: String) -> String? {
        switch name {
        case "Id": TrayMenuLayout.quote(self.id)
        case "Category": TrayMenuLayout.quote(self.category)
        case "Status": TrayMenuLayout.quote(self.status)
        case "IconName": TrayMenuLayout.quote(self.iconName)
        case "IconAccessibleDesc": TrayMenuLayout.quote(self.title)
        case "AttentionIconName": TrayMenuLayout.quote("")
        case "AttentionAccessibleDesc": TrayMenuLayout.quote("")
        case "Title": TrayMenuLayout.quote(self.title)
        case "IconThemePath": TrayMenuLayout.quote(self.iconThemePath)
        case "Menu": "objectpath \(TrayMenuLayout.quote(self.menuPath))"
        case "XAyatanaLabel": TrayMenuLayout.quote(self.label)
        case "XAyatanaLabelGuide": TrayMenuLayout.quote(self.labelGuide)
        case "XAyatanaOrderingIndex": "uint32 \(self.orderingIndex)"
        // (iconName, iconPixmaps, title, description)
        case "ToolTip":
            "(\(TrayMenuLayout.quote(self.iconName)), @a(iiay) [], "
                + "\(TrayMenuLayout.quote(self.title)), \(TrayMenuLayout.quote("")))"
        default: nil
        }
    }
}
