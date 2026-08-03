import CGtk4
import Foundation

/// One entry in the tray menu.
///
/// The same values drive both the `GMenu` handed to libayatana and the
/// `com.canonical.dbusmenu` layout served by `TrayMenuServer`, so the menu is
/// defined in exactly one place. `id` is the dbusmenu item id; 0 is reserved
/// for the root and must not be used.
public struct TrayMenuItem: Equatable, Sendable {
    public let id: Int32
    public let label: String
    /// The `GAction` name activated on click. `nil` for separators.
    public let actionName: String?
    public let isSeparator: Bool
    public let isEnabled: Bool

    public init(
        id: Int32,
        label: String,
        actionName: String?,
        isSeparator: Bool = false,
        isEnabled: Bool = true)
    {
        self.id = id
        self.label = label
        self.actionName = actionName
        self.isSeparator = isSeparator
        self.isEnabled = isEnabled
    }

    public static func separator(id: Int32) -> TrayMenuItem {
        TrayMenuItem(id: id, label: "", actionName: nil, isSeparator: true)
    }

    /// The action a `com.canonical.dbusmenu.Event` with this id should fire.
    /// Separators and unknown ids return nil, which the server treats as a no-op.
    public static func actionName(forID id: Int32, in items: [TrayMenuItem]) -> String? {
        items.first { $0.id == id }?.actionName
    }
}

/// Serializes a `[TrayMenuItem]` into GVariant **text format** for the
/// dbusmenu replies.
///
/// Text rather than `GVariantBuilder` because the reply types are recursive
/// (`(u(ia{sv}av))`) and text is the only form that can be asserted in a unit
/// test without a session bus. `parses(_:as:)` is the safety net: every
/// generated string is proven to parse under its declared type.
public enum TrayMenuLayout {
    /// dbusmenu properties, in a fixed order so the tests can pin the output.
    private static let orderedPropertyNames = ["label", "enabled", "visible", "type"]

    /// Wraps a string as a single-quoted GVariant literal.
    ///
    /// Backslashes first: escaping quotes first would then double the escape
    /// backslash and break the literal.
    public static func quote(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "'", with: "\\'")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        return "'\(escaped)'"
    }

    /// The `a{sv}` property dictionary for one item.
    ///
    /// An empty `propertyNames` means "every property", per the dbusmenu spec;
    /// a non-empty one filters. Separators carry no label — hosts that render
    /// one would draw an empty string next to the divider.
    static func propertyDictionary(
        for item: TrayMenuItem,
        propertyNames: [String]) -> String
    {
        var all: [String: String] = [
            "enabled": item.isEnabled ? "<true>" : "<false>",
            "visible": "<true>",
            "type": item.isSeparator ? "<'separator'>" : "<'standard'>",
        ]
        if !item.isSeparator {
            all["label"] = "<\(self.quote(item.label))>"
        }

        let wanted = propertyNames.isEmpty
            ? self.orderedPropertyNames
            : self.orderedPropertyNames.filter { propertyNames.contains($0) }
        let pairs = wanted.compactMap { name in
            all[name].map { "\(self.quote(name)): \($0)" }
        }
        return pairs.isEmpty ? "@a{sv} {}" : "{\(pairs.joined(separator: ", "))}"
    }

    /// Reply body for `GetLayout`, type `(u(ia{sv}av))`.
    ///
    /// The menu is flat: every item is a direct child of root id 0, and each
    /// child's own child array is empty.
    public static func layoutText(
        revision: UInt32,
        items: [TrayMenuItem],
        propertyNames: [String]) -> String
    {
        let children = items.map { item in
            "<(\(item.id), \(self.propertyDictionary(for: item, propertyNames: propertyNames)), @av [])>"
        }
        let childArray = children.isEmpty ? "@av []" : "[\(children.joined(separator: ", "))]"
        return "(\(revision), (0, {'children-display': <'submenu'>}, \(childArray)))"
    }

    /// Reply body for `GetGroupProperties`, type `(a(ia{sv}))`.
    /// An empty `ids` list means every item, per the spec.
    public static func groupPropertiesText(
        ids: [Int32],
        items: [TrayMenuItem],
        propertyNames: [String]) -> String
    {
        let selected = ids.isEmpty ? items : items.filter { ids.contains($0.id) }
        let entries = selected.map { item in
            "(\(item.id), \(self.propertyDictionary(for: item, propertyNames: propertyNames)))"
        }
        let array = entries.isEmpty ? "@a(ia{sv}) []" : "[\(entries.joined(separator: ", "))]"
        return "(\(array),)"
    }

    /// Reply body for `GetProperty`, type `(v)`. Nil when the item or the
    /// property does not exist, which the server answers as a DBus error.
    public static func propertyText(id: Int32, name: String, items: [TrayMenuItem]) -> String? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        let dictionary = self.propertyDictionary(for: item, propertyNames: [name])
        guard dictionary != "@a{sv} {}",
              let colon = dictionary.range(of: ": ")
        else {
            return nil
        }
        let value = dictionary[colon.upperBound...].dropLast() // trailing '}'
        return "(\(value),)"
    }

    /// True when `text` parses as `typeString`. Used by the tests to prove the
    /// generated strings are well formed, and by the server to fail loudly.
    public static func parses(_ text: String, as typeString: String) -> Bool {
        guard let variant = self.parseVariant(text: text, type: typeString) else { return false }
        g_variant_unref(variant)
        return true
    }

    /// Parses GVariant text under an explicit type. Returns a full (non-floating)
    /// reference the caller owns, or nil after logging the parse error.
    static func parseVariant(text: String, type typeString: String) -> OpaquePointer? {
        guard let type = g_variant_type_new(typeString) else { return nil }
        defer { g_variant_type_free(type) }
        var error: UnsafeMutablePointer<GError>?
        let variant = g_variant_parse(type, text, nil, nil, &error)
        if let error {
            let message = String(cString: error.pointee.message)
            FileHandle.standardError.write(Data(
                "codexbar: tray variant parse failed (\(typeString)): \(message)\n".utf8))
            g_error_free(error)
            return nil
        }
        return variant
    }
}
