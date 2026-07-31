import CodexBarLinuxKit
import Foundation

// Top-level code is main-actor isolated, but `onActivate` is a plain `@Sendable`
// callback invoked by the GTK main loop. These globals are confined to the GTK
// thread by construction — nothing else ever touches them.
nonisolated(unsafe) let app = GtkApplication(applicationID: "app.codexbar.linux")
nonisolated(unsafe) var window: GtkWindow?
nonisolated(unsafe) var webView: WebView?

app.onActivate = {
    let created = GtkWindow(application: app, title: "CodexBar", width: 420, height: 640)
    let view = WebView()
    view.loadBundledUI()
    created.setChild(view.widgetPointer)
    created.present()
    window = created
    webView = view
}

let status = app.run()
exit(status)
