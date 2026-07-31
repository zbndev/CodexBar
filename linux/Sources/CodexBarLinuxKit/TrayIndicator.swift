import CAyatanaAppIndicator
import Foundation

/// A StatusNotifierItem tray entry.
///
/// Uses the GLib build of libayatana-appindicator, whose menu is a `GMenu`
/// and whose actions are a `GSimpleActionGroup` — both GIO rather than
/// widgets, which is what lets it coexist with GTK4 in one process.
public final class TrayIndicator {
    private let indicator: OpaquePointer
    private let actions: OpaquePointer

    public var onShow: (@Sendable () -> Void)?
    public var onRefresh: (@Sendable () -> Void)?
    public var onSettings: (@Sendable () -> Void)?
    public var onQuit: (@Sendable () -> Void)?

    public init(id: String, iconName: String, title: String) {
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
    }

    private func installActions() {
        self.addAction(named: "show") { [weak self] in self?.onShow?() }
        self.addAction(named: "refresh") { [weak self] in self?.onRefresh?() }
        self.addAction(named: "settings") { [weak self] in self?.onSettings?() }
        self.addAction(named: "quit") { [weak self] in self?.onQuit?() }
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
        g_menu_append(menu, "Open CodexBar", "show")
        g_menu_append(menu, "Refresh", "refresh")
        g_menu_append(menu, "Settings", "settings")
        g_menu_append(menu, "Quit", "quit")
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
