import CGtk4
import Foundation

/// Hops work from Swift concurrency back onto the GTK main loop.
///
/// GTK must only be touched from the thread running the main loop, so every
/// result produced by a `Task` has to come back through here before it can
/// reach a widget or the web view.
public enum MainLoopDispatch {
    private final class WorkBox {
        let work: @Sendable () -> Void
        init(_ work: @escaping @Sendable () -> Void) { self.work = work }
    }

    public static func onMainLoop(_ work: @escaping @Sendable () -> Void) {
        let box = Unmanaged.passRetained(WorkBox(work)).toOpaque()
        g_idle_add_full(
            G_PRIORITY_DEFAULT_IDLE,
            { data in
                guard let data else { return 0 }
                let box = Unmanaged<WorkBox>.fromOpaque(data).takeUnretainedValue()
                box.work()
                return 0 // G_SOURCE_REMOVE: run once
            },
            box,
            { data in
                guard let data else { return }
                Unmanaged<WorkBox>.fromOpaque(data).release()
            })
    }
}
