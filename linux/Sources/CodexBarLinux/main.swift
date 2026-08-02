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
nonisolated(unsafe) var loginCoordinator: LoginCoordinator?
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
            let settings = coordinator?.linuxSettings() ?? LinuxSettings()
            var renderedPayload = payload
            renderedPayload.localization = LocalizationCatalog.load(locale: settings.language)
            renderedPayload.display = DisplayPreferences(settings: settings)
            bridge?.send(.snapshot(renderedPayload))
            switch settings.trayLabelStyle {
            case .none:
                tray?.setLabel("")
            case .highestPercent:
                if let highest = store?.highestUsedPercent() {
                    tray?.setLabel("\(Int(highest.rounded()))%")
                }
            }
        }
    }

    let madeCoordinator = SettingsCoordinator(
        configStore: CodexBarConfigStore(),
        settingsStore: LinuxSettingsStore(fileURL: LinuxSettingsStore.defaultURL()),
        onChange: {
            // Everything here touches GTK/WebKit or store state the main loop
            // owns, so it must run there. The captured state is the top-level
            // optionals, which are assigned before any save can fire.
            MainLoopDispatch.onMainLoop {
                guard let coordinator, let store else { return }
                let settings = coordinator.linuxSettings()
                store.applyRefreshInterval(settings.refreshInterval)
                store.reconcileProviders()
                if settings.trayLabelStyle == .none { tray?.setLabel("") }
                publishSettings()
            }
        })

    let madeLoginCoordinator = LoginCoordinator(application: app, settings: madeCoordinator)
    madeLoginCoordinator.onFinish = { _ in
        MainLoopDispatch.onMainLoop {
            madeCoordinator.republish()
            madeStore.refreshAll()
        }
    }

    // One presenter shared by the popup's footer button and the tray menu:
    // the window is built lazily and reused, so its bridge survives a close.
    let presentSettings: @Sendable () -> Void = {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(
                application: app,
                coordinator: madeCoordinator,
                loginCoordinator: madeLoginCoordinator,
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
                let settings = madeCoordinator.linuxSettings()
                var renderedPayload = madeStore.currentPayload()
                renderedPayload.localization = LocalizationCatalog.load(locale: settings.language)
                renderedPayload.display = DisplayPreferences(settings: settings)
                bridge?.send(.snapshot(renderedPayload))
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
              .replaceTokenAccounts, .updateQuotaWarnings, .startLogin, .cancelLogin,
              .addManagedCodexAccount, .reauthenticateManagedCodexAccount, .removeManagedCodexAccount,
              .selectManagedCodexAccount:
            break
        case .quit:
            app.quit()
        }
    }

    view.loadBundledUI()
    created.setChild(view.widgetPointer)
    // Without this the popup is destroyed the moment it is closed, taking its
    // web view with it, while `webView`, `bridge` and `window` above keep
    // pointing at the freed GObjects — the next snapshot push then walks a
    // dangling WebKitWebView and the process dies inside
    // webkit_web_view_evaluate_javascript. The settings window has always set
    // it for the same reason; the tray's own window never did.
    created.setHideOnClose(true)

    let madeTray = TrayIndicator(
        id: "codexbar",
        iconName: "utilities-system-monitor",
        title: "CodexBar",
        connection: app.dbusConnection)
    madeTray.onShow = {
        MainLoopDispatch.onMainLoop {
            if created.isVisible {
                created.hide()
            } else {
                created.present()
                // Only on the opening half of the toggle.
                if madeCoordinator.linuxSettings().refreshOnOpen {
                    madeStore.refreshAll()
                }
            }
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
    loginCoordinator = madeLoginCoordinator

    madeStore.applyRefreshInterval(madeCoordinator.linuxSettings().refreshInterval)
}

let status = app.run()
exit(status)
