import CGtk4
import Foundation

/// A top-level window. Must only be touched on the GTK main loop thread.
///
/// The C types are spelled `_GtkWindow` / `_GtkApplication` — their struct tags —
/// because the plain `GtkWindow` and `GtkApplication` typedef names are shadowed
/// inside this module by the Swift classes of the same name.
///
/// `@unchecked Sendable` because the instance is confined to the GTK main-loop
/// thread: callbacks that capture it (tray actions, refresh completions) only
/// ever touch it from inside `MainLoopDispatch.onMainLoop`.
public final class GtkWindow: @unchecked Sendable {
    public let pointer: OpaquePointer

    public init(application: GtkApplication, title: String, width: Int32, height: Int32) {
        guard let window = gtk_application_window_new(
            UnsafeMutablePointer<_GtkApplication>(application.pointer))
        else {
            fatalError("gtk_application_window_new returned NULL")
        }
        self.pointer = OpaquePointer(window)
        gtk_window_set_title(UnsafeMutablePointer<_GtkWindow>(self.pointer), title)
        gtk_window_set_default_size(UnsafeMutablePointer<_GtkWindow>(self.pointer), width, height)
    }

    public func present() {
        gtk_window_present(UnsafeMutablePointer<_GtkWindow>(self.pointer))
    }

    public func hide() {
        gtk_widget_set_visible(UnsafeMutablePointer<_GtkWidget>(self.pointer), 0)
    }

    public var isVisible: Bool {
        gtk_widget_get_visible(UnsafeMutablePointer<_GtkWidget>(self.pointer)) != 0
    }

    /// Replaces the window's content with `child`.
    public func setChild(_ child: OpaquePointer) {
        gtk_window_set_child(
            UnsafeMutablePointer<_GtkWindow>(self.pointer),
            UnsafeMutablePointer<_GtkWidget>(child))
    }
}
