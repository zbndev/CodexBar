import Foundation

/// A StatusNotifierItem tray entry.
///
/// Both halves of the protocol are served in-process:
/// `StatusNotifierItemServer` publishes the item, `TrayMenuServer` publishes
/// `com.canonical.dbusmenu` on the same object path. Neither needs
/// `libayatana-appindicator-glib`, which was GPL-3 and unavailable on every
/// distribution this project packages for except Arch.
///
/// `@unchecked Sendable` for the same reason as `GtkWindow`: the instance is
/// confined to the GTK main-loop thread, and both servers call back into it
/// from that same thread.
public final class TrayIndicator: @unchecked Sendable {
    private var itemServer: StatusNotifierItemServer?
    private var menuServer: TrayMenuServer?

    public var onShow: (@Sendable () -> Void)?
    public var onRefresh: (@Sendable () -> Void)?
    public var onSettings: (@Sendable () -> Void)?
    public var onQuit: (@Sendable () -> Void)?

    /// The tray menu, in display order. Ids are dbusmenu item ids and must be
    /// stable across launches: hosts cache them between `LayoutUpdated` signals.
    public static let menuItems: [TrayMenuItem] = [
        TrayMenuItem(id: 1, label: "Open CodexBar", actionName: "show"),
        TrayMenuItem(id: 2, label: "Refresh", actionName: "refresh"),
        TrayMenuItem(id: 3, label: "Settings", actionName: "settings"),
        TrayMenuItem(id: 4, label: "Quit", actionName: "quit"),
    ]

    /// - Parameter connection: the session bus, from `GtkApplication.dbusConnection`.
    ///   Passing nil skips registration entirely — the app runs without a tray
    ///   icon, which is better than refusing to start.
    /// - Parameter iconThemePath: a directory holding `<iconName>.png`, searched
    ///   ahead of the icon theme. Nil resolves `iconName` against the theme
    ///   alone, which is what an installed build wants.
    public init(
        id: String,
        iconName: String,
        title: String,
        connection: OpaquePointer?,
        iconThemePath: String? = nil)
    {
        guard let connection else { return }
        // The path libayatana used, kept so nothing else has to move.
        let path = "/org/ayatana/appindicator/\(id)"

        let menu = TrayMenuServer(
            connection: connection,
            objectPath: path,
            items: Self.menuItems,
            activate: { [weak self] action in self?.activate(action) })
        menu.register()
        self.menuServer = menu

        let item = StatusNotifierItemServer(
            connection: connection,
            objectPath: path,
            state: StatusNotifierItemState(
                id: id,
                title: title,
                iconName: iconName,
                iconThemePath: iconThemePath ?? "",
                menuPath: path))
        // A left click opens the popup, matching what the GAction did before.
        item.onActivate = { [weak self] in self?.activate("show") }
        item.onSecondaryActivate = { [weak self] in self?.activate("show") }
        item.register()
        self.itemServer = item
    }

    /// One place where a menu click and a direct activation converge, so they
    /// cannot diverge.
    private func activate(_ action: String) {
        switch action {
        case "show": self.onShow?()
        case "refresh": self.onRefresh?()
        case "settings": self.onSettings?()
        case "quit": self.onQuit?()
        default: break
        }
    }

    /// Text shown next to the tray icon. Empty string hides it.
    public func setLabel(_ text: String) {
        self.itemServer?.setLabel(text)
    }

    public func setIcon(named name: String) {
        self.itemServer?.setIcon(named: name)
    }
}
