import CWebKitGTK
import Foundation

/// Reads the cookies WebKit collected during a login and turns them into the
/// `Cookie:` header value Core stores in `ProviderConfig.cookieHeader`.
///
/// `soup_cookies_to_cookie_header()` looks like the tool for the last step but
/// takes a `GSList*`, while `webkit_cookie_manager_get_cookies_finish()`
/// returns a `GList*` — different types. The list is walked directly, which is
/// needed anyway to filter by cookie name.
public enum CookieHarvester {
    /// Collects cookies for each URI in order and joins them.
    ///
    /// Must be called on the GTK main-loop thread: it touches WebKit.
    public static func cookieHeader(
        webView: WebView,
        uris: [String],
        allowedNames: Set<String> = []) async -> String?
    {
        guard let session = webkit_web_view_get_network_session(
            UnsafeMutablePointer<WebKitWebView>(webView.pointer)),
            let manager = webkit_network_session_get_cookie_manager(session)
        else {
            return nil
        }

        var collected: [[(String, String)]] = []
        for uri in uris {
            let pairs = await self.pairs(manager: manager, uri: uri)
            collected.append(allowedNames.isEmpty
                ? pairs
                : pairs.filter { allowedNames.contains($0.0) })
        }
        let header = self.mergePairs(collected)
        return header.isEmpty ? nil : header
    }

    /// Later lists win on a repeated name: a cookie set on the more specific
    /// host is the more recent one for that session.
    public static func mergePairs(_ lists: [[(String, String)]]) -> String {
        var order: [String] = []
        var values: [String: String] = [:]
        for list in lists {
            for (name, value) in list {
                if values[name] == nil { order.append(name) }
                values[name] = value
            }
        }
        return order.compactMap { name in values[name].map { "\(name)=\($0)" } }
            .joined(separator: "; ")
    }

    private final class HarvestBox {
        let continuation: CheckedContinuation<[(String, String)], Never>
        init(_ continuation: CheckedContinuation<[(String, String)], Never>) {
            self.continuation = continuation
        }
    }

    private static func pairs(manager: OpaquePointer, uri: String) async -> [(String, String)] {
        await withCheckedContinuation { continuation in
            let box = Unmanaged.passRetained(HarvestBox(continuation)).toOpaque()
            // WebKitCookieManager is a final GObject type: OpaquePointer, no cast.
            webkit_cookie_manager_get_cookies(
                manager,
                uri,
                nil,
                Self.cookiesReadyThunk,
                box)
        }
    }

    private static let cookiesReadyThunk: GAsyncReadyCallback = { source, result, userData in
        guard let userData else { return }
        let box = Unmanaged<HarvestBox>.fromOpaque(userData)
        defer { box.release() }

        guard let source, let result else {
            box.takeUnretainedValue().continuation.resume(returning: [])
            return
        }
        var error: UnsafeMutablePointer<GError>?
        let list = webkit_cookie_manager_get_cookies_finish(
            OpaquePointer(source),
            result,
            &error)
        if let error {
            FileHandle.standardError.write(Data(
                "codexbar: cookie read failed: \(String(cString: error.pointee.message))\n".utf8))
            g_error_free(error)
        }

        var pairs: [(String, String)] = []
        var node = list
        while let current = node {
            if let cookie = current.pointee.data {
                let soupCookie = OpaquePointer(cookie)
                if let name = soup_cookie_get_name(soupCookie),
                   let value = soup_cookie_get_value(soupCookie)
                {
                    pairs.append((String(cString: name), String(cString: value)))
                }
            }
            node = current.pointee.next
        }
        if let list {
            g_list_free_full(list, { pointer in
                guard let pointer else { return }
                soup_cookie_free(OpaquePointer(pointer))
            })
        }
        box.takeUnretainedValue().continuation.resume(returning: pairs)
    }
}
