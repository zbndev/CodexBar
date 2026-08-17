import CAdwaita
import Foundation

/// Owns the libadwaita application object and the GTK main loop.
///
/// `AdwApplication` is a `GtkApplication` subclass on both sides of the Swift/C
/// boundary, so existing window and tray code keeps using the same lifecycle.
public final class AdwApplication: GtkApplication, @unchecked Sendable {
    override public init(applicationID: String) {
        // G_APPLICATION_DEFAULT_FLAGS aliases G_APPLICATION_FLAGS_NONE at value 0, and the
        // Clang importer keeps only the first of two enumerators sharing a value — so the
        // constant is unavailable in Swift under that name. 0 is the documented default.
        guard let app = adw_application_new(applicationID, GApplicationFlags(rawValue: 0)) else {
            fatalError("adw_application_new returned NULL for \(applicationID)")
        }
        super.init(pointer: OpaquePointer(app))
    }
}
