import CAyatanaAppIndicator
import Foundation

/// A StatusNotifierItem tray entry.
///
/// Uses the GLib build of libayatana-appindicator, whose menu is a `GMenu`
/// and whose actions are a `GSimpleActionGroup` — both GIO rather than
/// widgets, which is what lets it coexist with GTK4 in one process.
///
/// `@unchecked Sendable` for the same reason as `GtkWindow`: the instance is
/// confined to the GTK main-loop thread. The dbusmenu server calls back into
/// it from that same thread, through a `@Sendable` closure.
public final class TrayIndicator: @unchecked Sendable {
    private let indicator: OpaquePointer
    private let actions: OpaquePointer
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
    ///   Passing nil skips the dbusmenu registration — the icon still appears,
    ///   but its menu is invisible to non-GNOME hosts.
    public init(id: String, iconName: String, title: String, connection: OpaquePointer?) {
        guard let indicator = app_indicator_new(id, iconName, APP_INDICATOR_CATEGORY_APPLICATION_STATUS) else {
            fatalError("app_indicator_new returned NULL")
        }
        self.indicator = OpaquePointer(indicator)

        guard let group = g_simple_action_group_new() else {
            fatalError("g_simple_action_group_new returned NULL")
        }
        self.actions = OpaquePointer(group)

        app_indicator_set_title(indicator, title)
        app_indicator_set_status(indicator, APP_INDICATOR_STATUS_ACTIVE)

        self.installActions()
        self.installMenu()

        if let connection {
            // The path libayatana exports and points its `Menu` property at.
            let server = TrayMenuServer(
                connection: connection,
                objectPath: "/org/ayatana/appindicator/\(id)",
                items: Self.menuItems,
                activate: { [weak self] action in self?.activate(action) })
            server.register()
            self.menuServer = server
        }
    }

    /// Runs the same closure a `GAction` activation would, so a dbusmenu click
    /// and an `org.gtk.Actions` activation cannot diverge.
    private func activate(_ action: String) {
        switch action {
        case "show": self.onShow?()
        case "refresh": self.onRefresh?()
        case "settings": self.onSettings?()
        case "quit": self.onQuit?()
        default: break
        }
    }

    private func installActions() {
        for item in Self.menuItems {
            guard let name = item.actionName else { continue }
            self.addAction(named: name) { [weak self] in self?.activate(name) }
        }
        app_indicator_set_actions(
            UnsafeMutablePointer<AppIndicator>(self.indicator),
            UnsafeMutablePointer<GSimpleActionGroup>(self.actions))
    }

    fileprivate final class ActionBox {
        let work: () -> Void
        init(_ work: @escaping () -> Void) { self.work = work }
    }

    private func addAction(named name: String, work: @escaping () -> Void) {
        guard let action = g_simple_action_new(name, nil) else {
            fatalError("g_simple_action_new returned NULL for \(name)")
        }
        let box = Unmanaged.passRetained(ActionBox(work)).toOpaque()
        g_signal_connect_data(
            gpointer(action),
            "activate",
            unsafeBitCast(Self.activateThunk, to: GCallback.self),
            box,
            { data, _ in
                guard let data else { return }
                Unmanaged<ActionBox>.fromOpaque(data).release()
            },
            GConnectFlags(rawValue: 0))
        // GActionMap and GAction are GInterfaces with no public struct, so Swift
        // imports both as bare OpaquePointer — no cast needed.
        g_action_map_add_action(self.actions, action)
    }

    private static let activateThunk: @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { _, _, data in
            guard let data else { return }
            Unmanaged<ActionBox>.fromOpaque(data).takeUnretainedValue().work()
        }

    private func installMenu() {
        guard let menu = g_menu_new() else {
            fatalError("g_menu_new returned NULL")
        }
        for item in Self.menuItems {
            guard let action = item.actionName else { continue }
            g_menu_append(menu, item.label, action)
        }
        app_indicator_set_menu(UnsafeMutablePointer<AppIndicator>(self.indicator), menu)
    }

    /// Text shown next to the tray icon. Empty string hides it.
    public func setLabel(_ text: String) {
        app_indicator_set_label(UnsafeMutablePointer<AppIndicator>(self.indicator), text, "")
    }

    public func setIcon(named name: String) {
        app_indicator_set_icon(UnsafeMutablePointer<AppIndicator>(self.indicator), name, "")
    }
}
