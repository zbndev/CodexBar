import CodexBarLinuxKit
import Foundation

// Top-level code is main-actor isolated, but `onActivate` is a plain `@Sendable`
// callback invoked by the GTK main loop. These globals are confined to the GTK
// thread by construction — nothing else ever touches them.
nonisolated(unsafe) let app = GtkApplication(applicationID: "app.codexbar.linux")
nonisolated(unsafe) var window: GtkWindow?
nonisolated(unsafe) var webView: WebView?
nonisolated(unsafe) var bridge: Bridge?

app.onActivate = {
    let created = GtkWindow(application: app, title: "CodexBar", width: 420, height: 640)
    let view = WebView()

    let madeBridge = Bridge(webView: view) { command in
        switch command {
        case .ready:
            FileHandle.standardError.write(Data("codexbar: web UI ready\n".utf8))
        case .quit:
            app.quit()
        case .refresh, .selectProvider, .openURL:
            FileHandle.standardError.write(Data("codexbar: command \(command)\n".utf8))
        }
    }

    view.loadBundledUI()
    created.setChild(view.widgetPointer)
    created.present()

    window = created
    webView = view
    bridge = madeBridge
}

let status = app.run()
exit(status)
