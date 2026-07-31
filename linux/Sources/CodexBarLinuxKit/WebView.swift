import CWebKitGTK
import Foundation

/// Resolves files shipped in the module bundle under `WebUI/`.
public enum WebUIResources {
    public static func directory() -> URL {
        Bundle.module.resourceURL!.appendingPathComponent("WebUI", isDirectory: true)
    }

    public static func url(forResource name: String) -> URL {
        self.directory().appendingPathComponent(name)
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
    }

    /// The widget pointer, for handing to `GtkWindow.setChild(_:)`.
    public var widgetPointer: OpaquePointer { self.pointer }

    /// Loads `index.html` from the bundle, with the bundle directory as base URI
    /// so relative `style.css` and `app.js` references resolve.
    public func loadBundledUI() {
        let indexURL = WebUIResources.url(forResource: "index.html")
        let html: String
        do {
            html = try String(contentsOf: indexURL, encoding: .utf8)
        } catch {
            fatalError("Failed to read bundled index.html at \(indexURL.path): \(error)")
        }
        let baseURI = WebUIResources.directory().absoluteString
        webkit_web_view_load_html(
            UnsafeMutablePointer<WebKitWebView>(self.pointer),
            html,
            baseURI)
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
