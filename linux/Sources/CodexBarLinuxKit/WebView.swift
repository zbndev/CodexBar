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
    private let policy: NavigationPolicy

    fileprivate final class PolicyBox {
        let policy: NavigationPolicy
        init(_ policy: NavigationPolicy) { self.policy = policy }
    }

    /// - Parameter networkSession: when non-nil, the view is constructed on
    ///   that session instead of the default one. Used by the cookie login
    ///   window to start from a signed-out state every time.
    public init(policy: NavigationPolicy = .appSchemeOnly, networkSession: OpaquePointer? = nil) {
        self.policy = policy

        if let networkSession {
            guard let view = Self.makeWebView(networkSession: networkSession) else {
                fatalError("g_object_new_with_properties(WebKitWebView) returned NULL")
            }
            self.pointer = view
        } else {
            guard let view = webkit_web_view_new() else {
                fatalError("webkit_web_view_new returned NULL")
            }
            self.pointer = OpaquePointer(view)
        }

        // Retained for the view's lifetime so the C policy callback can reach
        // the policy; the destroy notify below releases it.
        let box = Unmanaged.passRetained(PolicyBox(policy))
        g_signal_connect_data(
            gpointer(self.pointer),
            "decide-policy",
            unsafeBitCast(Self.policyThunk, to: GCallback.self),
            box.toOpaque(),
            { data, _ in
                guard let data else { return }
                Unmanaged<PolicyBox>.fromOpaque(data).release()
            },
            GConnectFlags(rawValue: 0))
    }

    /// `webkit_web_view_new()` always uses the default session, and
    /// `network-session` is construct-only, so the view has to be built
    /// through GObject. `g_object_new_with_properties` is the non-variadic
    /// form Swift can actually call.
    private static func makeWebView(networkSession: OpaquePointer) -> OpaquePointer? {
        var value = GValue()
        g_value_init(&value, webkit_network_session_get_type())
        g_value_set_object(&value, gpointer(networkSession))
        defer { g_value_unset(&value) }

        return "network-session".withCString { name -> OpaquePointer? in
            var names: [UnsafePointer<CChar>?] = [name]
            let values = [value]
            let object = names.withUnsafeMutableBufferPointer { nameBuffer in
                values.withUnsafeBufferPointer { valueBuffer in
                    g_object_new_with_properties(
                        webkit_web_view_get_type(),
                        1,
                        nameBuffer.baseAddress,
                        valueBuffer.baseAddress)
                }
            }
            return object.map(OpaquePointer.init)
        }
    }

    /// A private, empty cookie/data store. Every login therefore starts signed
    /// out — reusing a session would silently re-harvest the previous
    /// account's cookies when the user asked to add a different one.
    /// `WebKitNetworkSession` is a final GObject type, so the importer gives it
    /// as a non-optional `OpaquePointer` — no unwrapping to do here.
    public static func ephemeralNetworkSession() -> OpaquePointer? {
        webkit_network_session_new_ephemeral()
    }

    /// Loads an absolute URL. Only meaningful under `.anyHTTPS`; under
    /// `.appSchemeOnly` the policy handler rejects it.
    public func load(url: String) {
        webkit_web_view_load_uri(UnsafeMutablePointer<WebKitWebView>(self.pointer), url)
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
        UnsafeMutableRawPointer?) -> gboolean = { _, decision, type, data in
            guard type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION ||
                type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION,
                let decision
            else { return 0 }
            let policy = data
                .map { Unmanaged<PolicyBox>.fromOpaque($0).takeUnretainedValue().policy }
                ?? .appSchemeOnly
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
            if WebView.isNavigationAllowed(uri: String(cString: uriCString), policy: policy) {
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

extension WebView {
    /// What a web view is allowed to navigate to.
    public enum NavigationPolicy: Equatable, Sendable {
        /// The app UI: only `codexbar://`. Nothing can walk the view onto the
        /// network.
        case appSchemeOnly
        /// The cookie login window: any `https:` host, because provider logins
        /// legitimately redirect through identity providers. Everything else —
        /// `http:`, `file:`, custom schemes — stays blocked.
        case anyHTTPS
    }

    public static func isNavigationAllowed(uri: String, policy: NavigationPolicy) -> Bool {
        switch policy {
        case .appSchemeOnly:
            uri.hasPrefix("\(WebUIProtocol.scheme)://")
        case .anyHTTPS:
            uri.hasPrefix("https://")
        }
    }
}
