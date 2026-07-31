import CWebKitGTK
import Foundation

/// Serves the bundled web UI under the `codexbar://` scheme and keeps the
/// web layer off the network.
///
/// Registering a real scheme gives the page an origin, which is what makes
/// two spec requirements enforceable: the CSP in `index.html`/`settings.html`
/// can name `codexbar:` as the only source, and the `decide-policy` handler
/// in `WebView` can reject every navigation outside it.
public enum WebUIProtocol {
    public static let scheme = "codexbar"
    /// GTK/WebKit startup is main-loop confined; this guard makes repeated
    /// `activate` signals harmless without introducing a lock.
    nonisolated(unsafe) private static var isRegistered = false

    /// Registers the scheme on the default WebKit context. Must run before
    /// the first `WebView` is created; registration is global to the process,
    /// so the popup and the settings window share it.
    public static func register() {
        guard !self.isRegistered else { return }
        self.isRegistered = true
        guard let context = webkit_web_context_get_default() else {
            fatalError("webkit_web_context_get_default returned NULL")
        }
        webkit_web_context_register_uri_scheme(
            context,
            self.scheme,
            { request, _ in
                guard let request else { return }
                Self.handle(request: request)
            },
            nil,
            nil)
    }

    /// `WebKitURISchemeRequest` is declared with `WEBKIT_DECLARE_FINAL_TYPE`,
    /// so its struct stays opaque and Swift imports the pointer as
    /// `OpaquePointer` rather than a typed pointer.
    private static func handle(request: OpaquePointer) {
        let uri: String = {
            guard let cString = webkit_uri_scheme_request_get_uri(request) else { return "" }
            return String(cString: cString)
        }()

        guard let resource = self.resource(forURI: uri) else {
            let error = g_error_new_literal(
                g_quark_from_static_string("codexbar"), 1, "not found")
            webkit_uri_scheme_request_finish_error(request, error)
            g_error_free(error)
            return
        }

        // WebKit reads the stream after this call returns, so the bytes must
        // outlive the local array — hand GLib its own copy and let the stream
        // free it.
        let copied: gpointer? = resource.data.withUnsafeBytes { buffer in
            g_memdup2(buffer.baseAddress, gsize(buffer.count))
        }
        guard let stream = g_memory_input_stream_new_from_data(
            copied, gssize(resource.data.count), { data in g_free(data) })
        else {
            if let copied { g_free(copied) }
            return
        }
        webkit_uri_scheme_request_finish(
            request,
            stream,
            gint64(resource.data.count),
            resource.mimeType)
        g_object_unref(stream)
    }

    /// Maps a `codexbar://ui/<name>` URI to a bundled file. Pure and
    /// testable: no WebKit types involved.
    public static func resource(forURI uri: String) -> (data: Data, mimeType: String)? {
        guard uri.hasPrefix("\(self.scheme)://") else { return nil }
        let path = String(uri.dropFirst("\(self.scheme)://".count))
        // Strip the host component ("ui"); the path is what follows it.
        guard let slash = path.firstIndex(of: "/") else { return nil }
        let name = String(path[path.index(after: slash)...])

        // Reject traversal: the name must be a single relative path with no
        // parent references.
        guard !name.isEmpty,
              !name.hasPrefix("/"),
              !name.split(separator: "/").contains("..")
        else { return nil }

        let url = WebUIResources.directory().appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (data, self.mimeType(forPathExtension: url.pathExtension.lowercased()))
    }

    public static func mimeType(forPathExtension ext: String) -> String {
        switch ext {
        case "html": "text/html"
        case "css": "text/css"
        case "js": "text/javascript"
        case "json": "application/json"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "woff2": "font/woff2"
        default: "application/octet-stream"
        }
    }
}
