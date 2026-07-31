import CodexBarLinuxKit
import Foundation

// Top-level code is main-actor isolated, but the GTK callbacks below are plain
// `@Sendable` closures invoked by the GTK main loop. These globals are confined
// to the GTK thread by construction — nothing else ever touches them.
nonisolated(unsafe) let app = GtkApplication(applicationID: "app.codexbar.linux")
nonisolated(unsafe) var window: GtkWindow?
nonisolated(unsafe) var webView: WebView?
nonisolated(unsafe) var bridge: Bridge?
nonisolated(unsafe) var tray: TrayIndicator?
nonisolated(unsafe) var store: LinuxUsageStore?

/// Opens a URL in the user's default browser. Used for dashboard and status
/// links; the OAuth flows in M4 will reuse it.
func openInBrowser(_ url: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
    process.arguments = [url]
    try? process.run()
}

app.onActivate = {
    let created = GtkWindow(application: app, title: "CodexBar", width: 420, height: 640)
    let view = WebView()

    // Publishing goes through the main loop: snapshots arrive on background
    // tasks, and WebKit may only be touched from the GTK thread.
    let madeStore = LinuxUsageStore { payload in
        MainLoopDispatch.onMainLoop {
            bridge?.send(.snapshot(payload))
            if let highest = store?.highestUsedPercent() {
                tray?.setLabel("\(Int(highest.rounded()))%")
            }
        }
    }

    let madeBridge = Bridge(webView: view) { command in
        switch command {
        case .ready:
            MainLoopDispatch.onMainLoop {
                bridge?.send(.snapshot(madeStore.currentPayload()))
            }
            madeStore.refreshAll()
        case let .refresh(provider):
            MainLoopDispatch.onMainLoop {
                bridge?.send(.refreshStarted(provider: provider))
            }
            if let provider {
                madeStore.refresh(providerID: provider)
            } else {
                madeStore.refreshAll()
            }
        case let .openURL(url):
            openInBrowser(url)
        case .selectProvider:
            break
        case .quit:
            app.quit()
        }
    }

    view.loadBundledUI()
    created.setChild(view.widgetPointer)

    let madeTray = TrayIndicator(
        id: "codexbar",
        iconName: "utilities-system-monitor",
        title: "CodexBar")
    madeTray.onShow = {
        MainLoopDispatch.onMainLoop {
            if created.isVisible { created.hide() } else { created.present() }
        }
    }
    madeTray.onRefresh = { madeStore.refreshAll() }
    madeTray.onQuit = { MainLoopDispatch.onMainLoop { app.quit() } }

    window = created
    webView = view
    bridge = madeBridge
    tray = madeTray
    store = madeStore

    madeStore.startPeriodicRefresh(intervalSeconds: 300)
}

let status = app.run()
exit(status)
