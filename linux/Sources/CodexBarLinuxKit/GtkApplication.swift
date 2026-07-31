import CGtk4
import Foundation

/// Owns the GTK application object and the main loop.
///
/// GTK is not thread-safe: every call in this type, and in `GtkWindow`,
/// must happen on the thread that calls `run()`. Work coming off Swift
/// concurrency hops back through `MainLoopDispatch`.
///
/// `@unchecked Sendable` for the same reason as `GtkWindow`: the instance is
/// confined to the GTK main-loop thread, and callbacks reach it only through
/// `MainLoopDispatch.onMainLoop`.
public final class GtkApplication: @unchecked Sendable {
    public let pointer: OpaquePointer

    /// Called once GTK has finished starting up. Create windows here, not before.
    public var onActivate: (@Sendable () -> Void)?

    public init(applicationID: String) {
        // G_APPLICATION_DEFAULT_FLAGS aliases G_APPLICATION_FLAGS_NONE at value 0, and the
        // Clang importer keeps only the first of two enumerators sharing a value — so the
        // constant is unavailable in Swift under that name. 0 is the documented default.
        guard let app = gtk_application_new(applicationID, GApplicationFlags(rawValue: 0)) else {
            fatalError("gtk_application_new returned NULL for \(applicationID)")
        }
        self.pointer = OpaquePointer(app)
    }

    /// Runs the GTK main loop. Returns only when the application quits.
    public func run() -> Int32 {
        let box = Unmanaged.passRetained(ActivateBox(self)).toOpaque()
        g_signal_connect_data(
            gpointer(self.pointer),
            "activate",
            unsafeBitCast(Self.activateThunk, to: GCallback.self),
            box,
            { data, _ in
                guard let data else { return }
                Unmanaged<ActivateBox>.fromOpaque(data).release()
            },
            GConnectFlags(rawValue: 0))
        return g_application_run(UnsafeMutablePointer<_GApplication>(self.pointer), 0, nil)
    }

    public func quit() {
        g_application_quit(UnsafeMutablePointer<_GApplication>(self.pointer))
    }

    fileprivate final class ActivateBox {
        let owner: GtkApplication
        init(_ owner: GtkApplication) { self.owner = owner }
    }

    private static let activateThunk: @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { _, data in
            guard let data else { return }
            let box = Unmanaged<ActivateBox>.fromOpaque(data).takeUnretainedValue()
            box.owner.onActivate?()
        }
}
