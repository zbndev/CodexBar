import Foundation

/// Widget tests need a display server. Without one they skip rather than crash,
/// so `swift test` stays usable over SSH and in a bare container. CI runs them
/// under `xvfb-run -a`, which sets DISPLAY.
enum DisplayGate {
    static var available: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["DISPLAY"] != nil || environment["WAYLAND_DISPLAY"] != nil
    }
}
