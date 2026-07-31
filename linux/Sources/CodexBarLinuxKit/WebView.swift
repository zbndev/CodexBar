import CWebKitGTK
import Foundation

/// Resolves files shipped in the module bundle under `WebUI/`.
public enum WebUIResources {
    public static func directory() -> URL {
        Bundle.module.resourceURL!.appendingPathComponent("WebUI", isDirectory: true)
    }

}

/// A WebKit view hosting the local UI. Main-loop thread only.
public final class WebView {
    public let pointer: OpaquePointer

    public init() {
        guard let view = webkit_web_view_new() else {
            fatalError("webkit_web_view_new returned NULL")
        }
        self.pointer = OpaquePointer(view)

        g_signal_connect_data(
            gpointer(self.pointer),
            "decide-policy",
            unsafeBitCast(Self.policyThunk, to: GCallback.self),
            nil,
            nil,
            GConnectFlags(rawValue: 0))
    }

    /// The widget pointer, for handing to `GtkWindow.setChild(_:)`.
    public var widgetPointer: OpaquePointer { self.pointer }

    /// Loads a bundled page through the `codexbar://` scheme.
    ///
    /// `WebUIProtocol.register()` must already have run, otherwise WebKit has
    /// no handler for the scheme and the view stays blank.
    public func loadBundledUI(page: String = "index.html") {
        webkit_web_view_load_uri(
            UnsafeMutablePointer<WebKitWebView>(self.pointer),
            "\(WebUIProtocol.scheme)://ui/\(page)")
    }

    /// Allows navigations inside the app scheme only. Everything else —
    /// http(s), file, about — is ignored, so a compromised or buggy page
    /// cannot walk the web view out to the network.
    ///
    /// New-window actions are handled alongside ordinary navigations so an
    /// external link cannot escape through a second web view either.
    /// `WebKitPolicyDecision` is a derivable type (a real struct), while its
    /// `WebKitNavigationPolicyDecision` subclass is final and therefore
    /// opaque — hence the pointer conversion below.
    private static let policyThunk: @convention(c) (
        OpaquePointer?,
        UnsafeMutablePointer<WebKitPolicyDecision>?,
        WebKitPolicyDecisionType,
        UnsafeMutableRawPointer?) -> gboolean = { _, decision, type, _ in
            guard type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION ||
                type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION,
                let decision
            else { return 0 }
            // WebKitGTK 6 removed `webkit_navigation_policy_decision_get_request`;
            // the request is reached through the navigation action instead.
            guard let action = webkit_navigation_policy_decision_get_navigation_action(
                OpaquePointer(decision)),
                  let request = webkit_navigation_action_get_request(action),
                  let uriCString = webkit_uri_request_get_uri(request)
            else {
                webkit_policy_decision_ignore(decision)
                return 1
            }
            if String(cString: uriCString).hasPrefix("\(WebUIProtocol.scheme)://") {
                webkit_policy_decision_use(decision)
            } else {
                webkit_policy_decision_ignore(decision)
            }
            return 1
        }

    /// Runs JavaScript in the page. Fire-and-forget: results are ignored.
    public func evaluate(javaScript script: String) {
        webkit_web_view_evaluate_javascript(
            UnsafeMutablePointer<WebKitWebView>(self.pointer),
            script,
            -1,
            nil,
            nil,
            nil,
            nil,
            nil)
    }
}
