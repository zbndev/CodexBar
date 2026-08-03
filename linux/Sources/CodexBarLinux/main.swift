import CodexBarCore
import CodexBarLinuxKit
import Foundation

// Ahead of every GTK and D-Bus call: the packaging jobs run this in a
// container with no display and no session bus, purely to prove the artifact
// executes and reports the version it claims on its filename.
if CommandLine.arguments.dropFirst().contains("--version") {
    print("CodexBar for Linux \(LinuxAppInfo.version)")
    exit(0)
}

// Top-level code is main-actor isolated, but the GTK callbacks below are plain
// `@Sendable` closures invoked by the GTK main loop. These globals are confined
// to the GTK thread by construction — nothing else ever touches them.
let app = GtkApplication(applicationID: "app.codexbar.linux")
nonisolated(unsafe) var window: GtkWindow?
nonisolated(unsafe) var webView: WebView?
nonisolated(unsafe) var bridge: Bridge?
nonisolated(unsafe) var tray: TrayIndicator?
nonisolated(unsafe) var store: LinuxUsageStore?
nonisolated(unsafe) var costStore: LinuxCostStore?
nonisolated(unsafe) var diagnosticsStore: LinuxDiagnosticsStore?
nonisolated(unsafe) var cacheController: LinuxCacheController?
nonisolated(unsafe) var statusPoller: ProviderStatusPoller?
nonisolated(unsafe) var agentSessionsStore: LinuxAgentSessionsStore?
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
    let kiloOrganizations = KiloOrganizationsState()
    // A finished cost scan must reach both surfaces: the popup snapshot gains
    // the provider's cost, and an open Usage & Spend pane re-renders.
    let madeCostStore = LinuxCostStore(onChange: {
        MainLoopDispatch.onMainLoop {
            store?.republish()
            publishSettings()
        }
    })
    let madeDiagnosticsStore = LinuxDiagnosticsStore()
    let madeCacheController = LinuxCacheController()
    let settingsStore = LinuxSettingsStore(fileURL: LinuxSettingsStore.defaultURL())
    let notificationCoordinator = LinuxNotificationCoordinator()
    let madeAgentSessionsStore = LinuxAgentSessionsStore(onChange: {
        MainLoopDispatch.onMainLoop {
            store?.republish()
            store?.codingActivityDidChange()
        }
    })
    let madeStore = LinuxUsageStore(
        kiloOrganizations: kiloOrganizations,
        onKiloOrganizationsChange: { MainLoopDispatch.onMainLoop { publishSettings() } },
        costStore: madeCostStore,
        onRefreshRecord: { record in
            guard let provider = UsageProvider(rawValue: record.view.id) else { return }
            madeDiagnosticsStore.record(.init(
                provider: provider,
                descriptor: ProviderDescriptorRegistry.descriptor(for: provider),
                outcome: record.outcome,
                sourceMode: .auto,
                settings: nil,
                auth: ProviderDiagnosticAuthSummary(configured: false, modes: []),
                appVersion: LinuxAppInfo.version))
        },
        notificationCoordinator: notificationCoordinator,
        notificationSettings: {
            LinuxSettingsStore(fileURL: LinuxSettingsStore.defaultURL()).load()
        }, lastCodingActivityAt: {
            madeAgentSessionsStore.lastCodingActivityAt
        }) { payload in
        MainLoopDispatch.onMainLoop {
            let settings = coordinator?.linuxSettings() ?? LinuxSettings()
            var renderedPayload = payload
                .withAgentSessions(
                    madeAgentSessionsStore.currentPayload(),
                    enabled: settings.agentSessionsEnabled)
                .hidingPersonalInfo(settings.hidePersonalInfo)
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
        settingsStore: settingsStore,
        kiloOrganizations: kiloOrganizations,
        costViews: { madeCostStore.availableViews() },
        diagnosticsPayload: madeDiagnosticsStore.payload,
        cachePayload: madeCacheController.payload,
        onChange: {
            // Everything here touches GTK/WebKit or store state the main loop
            // owns, so it must run there. The captured state is the top-level
            // optionals, which are assigned before any save can fire.
            MainLoopDispatch.onMainLoop {
                guard let coordinator, let store else { return }
                let settings = coordinator.linuxSettings()
                store.applyRefreshInterval(settings.refreshInterval)
                madeAgentSessionsStore.setIncludeFileOnlySessions(settings.includeFileOnlySessions)
                 store.reconcileProviders()
                if settings.statusChecksEnabled { statusPoller?.start() } else { statusPoller?.stop() }
                if settings.trayLabelStyle == .none { tray?.setLabel("") }
                publishSettings()
            }
        })

    let madeLoginCoordinator = LoginCoordinator(application: app, settings: madeCoordinator)
    let madeStatusPoller = ProviderStatusPoller(
        statusChecksEnabled: {
            LinuxSettingsStore(fileURL: LinuxSettingsStore.defaultURL()).load().statusChecksEnabled
        },
        onTransition: { transition in
            MainLoopDispatch.onMainLoop { madeStore.applyStatusTransition(transition) }
        })
    madeLoginCoordinator.onFinish = { _ in
        MainLoopDispatch.onMainLoop {
            madeCoordinator.republish()
            madeStore.refreshAll()
        }
    }

    // Both surfaces send refreshCost for the provider they are showing; the
    // forced rescan's completion republishes through the onChange above.
    let refreshCost: @Sendable (String) -> Void = { providerID in
        guard let config = madeCoordinator.providerConfig(id: providerID) else { return }
        Task { await madeCostStore.refresh(providerID: providerID, config: config, forceRefresh: true) }
    }

    let shutdown: @Sendable () -> Void = {
        madeStore.stopPeriodicRefresh()
        madeStatusPoller.stop()
        madeLoginCoordinator.cancelAll()
        Task {
            await madeAgentSessionsStore.stop()
            MainLoopDispatch.onMainLoop { app.quit() }
        }
    }

    // One presenter shared by the popup's footer button and the tray menu:
    // the window is built lazily and reused, so its bridge survives a close.
    let presentSettings: @Sendable (String?) -> Void = { pane in
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(
                application: app,
                coordinator: madeCoordinator,
                loginCoordinator: madeLoginCoordinator,
                registerSink: { settingsEventSink = $0 },
                onRefresh: { madeStore.refreshAll() },
                onRefreshCost: refreshCost,
                 onTestHook: { event, providerID in await madeStore.testHook(event: event, provider: providerID) },
                 onTestNotification: { settings in await notificationCoordinator.testNotification(settings: settings) },
                onDiagnosticsCommand: { command in
                    switch command {
                    case .refreshDiagnostics:
                        madeStore.republish()
                    case .clearCostCache:
                        Task { _ = await madeCacheController.clearCostCache(); publishSettings() }
                    case .clearCookieCache:
                        _ = madeCacheController.clearCookieCache()
                        publishSettings()
                    case .refreshStorageFootprints:
                        let requests = ProviderDescriptorRegistry.all.map { descriptor in
                            LinuxStorageScanRequest(
                                provider: descriptor.id,
                                paths: ProviderStoragePathCatalog.candidatePaths(
                                    for: descriptor.id,
                                    environment: ProcessInfo.processInfo.environment))
                        }
                        _ = madeCacheController.refreshStorageFootprints(requests)
                        publishSettings()
                    case .exportDiagnostics:
                        if let data = try? madeDiagnosticsStore.exportData(), let window {
                            DiagnosticsExportSaver(data: data).present(from: window)
                        }
                    default:
                        break
                    }
                },
                onQuit: shutdown)
        }
        settingsWindow?.present(pane: pane)
        madeCoordinator.republish()
    }

    let madeBridge = Bridge(webView: view) { command in
        switch command {
        case .ready:
            MainLoopDispatch.onMainLoop {
                let settings = madeCoordinator.linuxSettings()
                var renderedPayload = madeStore.currentPayload()
                    .withAgentSessions(
                        madeAgentSessionsStore.currentPayload(),
                        enabled: settings.agentSessionsEnabled)
                    .hidingPersonalInfo(settings.hidePersonalInfo)
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
        case let .refreshCost(provider):
            refreshCost(provider)
        case let .openURL(url):
            SystemBrowser.open(url)
        case .selectProvider:
            break
        case .openSettings:
            MainLoopDispatch.onMainLoop { presentSettings(nil) }
        case let .openProviderSettings(providerID):
            MainLoopDispatch.onMainLoop {
                presentSettings(providerID.map { "provider:\($0)" })
            }
        // Handled by the settings window's own bridge, never the popup's.
        case .settingsReady, .updateProviderConfig, .updateSettings, .updateHooks, .openConfigFolder,
               .replaceTokenAccounts, .updateQuotaWarnings, .startLogin, .cancelLogin,
               .addManagedCodexAccount, .reauthenticateManagedCodexAccount, .removeManagedCodexAccount,
               .selectManagedCodexAccount, .refreshKiloOrganizations, .setKiloOrganizationEnabled,
                .refreshClaudeSwap, .switchClaudeSwapAccount, .testHook, .testNotification:
            break
        case .refreshDiagnostics:
            madeStore.republish()
            publishSettings()
        case .clearCostCache:
            Task { _ = await madeCacheController.clearCostCache(); publishSettings() }
        case .clearCookieCache:
            _ = madeCacheController.clearCookieCache()
            publishSettings()
        case .refreshStorageFootprints:
            let requests = ProviderDescriptorRegistry.all.map { descriptor in
                LinuxStorageScanRequest(
                    provider: descriptor.id,
                    paths: ProviderStoragePathCatalog.candidatePaths(
                        for: descriptor.id,
                        environment: ProcessInfo.processInfo.environment))
            }
            _ = madeCacheController.refreshStorageFootprints(requests)
            publishSettings()
        case .exportDiagnostics:
            if let data = try? madeDiagnosticsStore.exportData(), let window {
                DiagnosticsExportSaver(data: data).present(from: window)
            }
        case .openAbout:
            MainLoopDispatch.onMainLoop { presentSettings("about") }
        case .openUsageDashboard:
            MainLoopDispatch.onMainLoop { presentSettings("spend") }
        case let .openProviderStatus(providerID):
            let provider = providerID.flatMap { id in madeStore.currentPayload().providers.first { $0.id == id } }
            if let url = provider?.statusPageURL { SystemBrowser.open(url) }
        case .quit:
            shutdown()
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

    // The app's own icon when its asset is reachable, a stock name only as a
    // fallback — a tray with no resolvable icon shows nothing at all.
    let iconPlacement = AppIcon.placement()
    let madeTray = TrayIndicator(
        id: "codexbar",
        iconName: iconPlacement.name,
        title: "CodexBar",
        connection: app.dbusConnection,
        iconThemePath: iconPlacement.themePath)
    madeTray.onShow = {
        MainLoopDispatch.onMainLoop {
            if created.isVisible {
                madeAgentSessionsStore.setPopupOpen(false)
                created.hide()
            } else {
                madeAgentSessionsStore.setPopupOpen(true)
                madeStore.popupOpened()
                created.present()
                // Only on the opening half of the toggle.
                if madeCoordinator.linuxSettings().refreshOnOpen {
                    madeStore.refreshAll()
                }
            }
        }
    }
    madeTray.onRefresh = { madeStore.refreshAll() }
    madeTray.onSettings = { MainLoopDispatch.onMainLoop { presentSettings(nil) } }
    madeTray.onQuit = shutdown

    window = created
    webView = view
    bridge = madeBridge
    tray = madeTray
    store = madeStore
    costStore = madeCostStore
    diagnosticsStore = madeDiagnosticsStore
    cacheController = madeCacheController
    statusPoller = madeStatusPoller
    agentSessionsStore = madeAgentSessionsStore
    coordinator = madeCoordinator
    loginCoordinator = madeLoginCoordinator

    madeStore.applyRefreshInterval(madeCoordinator.linuxSettings().refreshInterval)
    madeAgentSessionsStore.setIncludeFileOnlySessions(madeCoordinator.linuxSettings().includeFileOnlySessions)
    madeAgentSessionsStore.start()
    madeStatusPoller.start()
}

let status = app.run()
exit(status)
