import CodexBarCore
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
nonisolated(unsafe) var settingsWindow: SettingsWindow?
nonisolated(unsafe) var coordinator: SettingsCoordinator?
nonisolated(unsafe) var settingsEventSink: (@Sendable (SettingsPayload) -> Void)?

/// Rebuilds the settings payload and pushes it to the settings window, if one
/// is open. Runs on the main loop because it ends in a WebKit call.
func publishSettings() {
    MainLoopDispatch.onMainLoop {
        guard let coordinator else { return }
        settingsEventSink?(coordinator.payload())
    }
}

app.onActivate = {
    // Must precede the first WebView: the scheme is registered on the default
    // web context, and a view created earlier would have nothing to load from.
    WebUIProtocol.register()

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

    let madeCoordinator = SettingsCoordinator(
        configStore: CodexBarConfigStore(),
        settingsStore: LinuxSettingsStore(fileURL: LinuxSettingsStore.defaultURL()),
        onChange: { publishSettings() })

    // One presenter shared by the popup's footer button and the tray menu:
    // the window is built lazily and reused, so its bridge survives a close.
    let presentSettings: @Sendable () -> Void = {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(
                application: app,
                coordinator: madeCoordinator,
                registerSink: { settingsEventSink = $0 },
                onRefresh: { madeStore.refreshAll() },
                onQuit: { MainLoopDispatch.onMainLoop { app.quit() } })
        }
        settingsWindow?.present()
        madeCoordinator.republish()
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
            SystemBrowser.open(url)
        case .selectProvider:
            break
        case .openSettings:
            MainLoopDispatch.onMainLoop { presentSettings() }
        // Handled by the settings window's own bridge, never the popup's.
        case .settingsReady, .updateProviderConfig, .updateSettings, .updateHooks, .openConfigFolder,
             .replaceTokenAccounts, .updateQuotaWarnings:
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
    madeTray.onSettings = { MainLoopDispatch.onMainLoop { presentSettings() } }
    madeTray.onQuit = { MainLoopDispatch.onMainLoop { app.quit() } }

    window = created
    webView = view
    bridge = madeBridge
    tray = madeTray
    store = madeStore
    coordinator = madeCoordinator

    madeStore.startPeriodicRefresh(intervalSeconds: 300)
}

let status = app.run()
exit(status)
