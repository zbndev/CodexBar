import CAdwaita
import Foundation

/// Connects Swift closures to GObject signals.
///
/// The closure is retained in a box for the connection's lifetime and released
/// by the destroy notify, which is what makes `g_signal_connect_data` safe to
/// call with a Swift closure at all.
public enum Signal {
    fileprivate final class Box {
        let handler: @Sendable () -> Void
        init(_ handler: @escaping @Sendable () -> Void) { self.handler = handler }
    }

    /// Connects a handler that ignores whatever the signal carries.
    ///
    /// The connection is made swapped. Unswapped, GLib calls the handler as
    /// `(instance, extra…, data)` — the user data is *last*, so its position
    /// depends on the signal's arity and a single thunk cannot find it
    /// (`GtkButton::clicked` passes two arguments, `GSimpleAction::activate`
    /// three). `G_CONNECT_SWAPPED` exchanges instance and data, making the call
    /// `(data, extra…, instance)` — the box is always first, and everything
    /// after it is a trailing argument the C calling convention lets the callee
    /// ignore. That is what makes one thunk correct for every void signal.
    public static func connect(
        _ object: OpaquePointer,
        _ name: String,
        _ handler: @escaping @Sendable () -> Void)
    {
        let box = Unmanaged.passRetained(Box(handler)).toOpaque()
        g_signal_connect_data(
            gpointer(object),
            name,
            unsafeBitCast(self.thunk, to: GCallback.self),
            box,
            { data, _ in
                guard let data else { return }
                Unmanaged<Box>.fromOpaque(data).release()
            },
            // The destroy notify still receives the unswapped user data, so the
            // box is released exactly once when the object drops the handler.
            // Spelled `CONNECT_SWAPPED` rather than `.swapped`: `G_CONNECT_DEFAULT`
            // breaks the common-prefix run the importer strips, so only `G_` goes.
            GConnectFlags.CONNECT_SWAPPED)
    }

    private static let thunk: @convention(c) (UnsafeMutableRawPointer?) -> Void = { data in
        guard let data else { return }
        Unmanaged<Box>.fromOpaque(data).takeUnretainedValue().handler()
    }
}
