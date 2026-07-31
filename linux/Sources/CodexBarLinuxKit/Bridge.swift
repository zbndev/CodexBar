import CWebKitGTK
import Foundation

/// Carries `BridgeCommand` from JS to Swift and `BridgeEvent` back.
///
/// JS side: `window.webkit.messageHandlers.codexbar.postMessage(jsonString)`.
/// Swift side: `window.__codexbar.receive(jsonString)`.
public final class Bridge {
    private let webView: WebView
    private let handler: @Sendable (BridgeCommand) -> Void
    private let encoder = JSONEncoder()

    /// Retained for the lifetime of the process; released when the bridge dies.
    private var selfBox: Unmanaged<BridgeBox>?

    fileprivate final class BridgeBox {
        weak var bridge: Bridge?
        init(_ bridge: Bridge) { self.bridge = bridge }
    }

    public init(webView: WebView, handler: @escaping @Sendable (BridgeCommand) -> Void) {
        self.webView = webView
        self.handler = handler
        self.registerHandler()
    }

    private func registerHandler() {
        guard let manager = webkit_web_view_get_user_content_manager(
            UnsafeMutablePointer<WebKitWebView>(self.webView.pointer))
        else {
            fatalError("webkit_web_view_get_user_content_manager returned NULL")
        }

        // The third argument is the script world; nil means the default world.
        webkit_user_content_manager_register_script_message_handler(manager, "codexbar", nil)

        let box = Unmanaged.passRetained(BridgeBox(self))
        self.selfBox = box
        g_signal_connect_data(
            gpointer(manager),
            "script-message-received::codexbar",
            unsafeBitCast(Self.messageThunk, to: GCallback.self),
            box.toOpaque(),
            { data, _ in
                guard let data else { return }
                Unmanaged<BridgeBox>.fromOpaque(data).release()
            },
            GConnectFlags(rawValue: 0))
    }

    private static let messageThunk: @convention(c) (
        UnsafeMutableRawPointer?, OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, value, data in
            guard let data, let value else { return }
            let box = Unmanaged<BridgeBox>.fromOpaque(data).takeUnretainedValue()
            guard let bridge = box.bridge else { return }
            guard let cString = jsc_value_to_string(value) else { return }
            defer { g_free(cString) }
            let json = String(cString: cString)
            bridge.dispatch(json: json)
        }

    private func dispatch(json: String) {
        do {
            let command = try JSONDecoder().decode(BridgeCommand.self, from: Data(json.utf8))
            self.handler(command)
        } catch {
            FileHandle.standardError.write(Data(
                "codexbar: undecodable bridge message \(json): \(error)\n".utf8))
        }
    }

    /// Sends an event to the web UI. Must be called on the main loop thread.
    public func send(_ event: BridgeEvent) {
        do {
            let data = try self.encoder.encode(event)
            let json = String(decoding: data, as: UTF8.self)
            let literal = BridgeScriptEncoding.javaScriptStringLiteral(json)
            self.webView.evaluate(javaScript: "window.__codexbar && window.__codexbar.receive(\(literal));")
        } catch {
            FileHandle.standardError.write(Data("codexbar: failed to encode event: \(error)\n".utf8))
        }
    }
}
