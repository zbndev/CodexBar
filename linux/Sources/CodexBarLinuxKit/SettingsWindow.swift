import CodexBarCore
import Foundation

/// The settings window: a decorated window with its own web view and
/// bridge, fed by `SettingsCoordinator`.
///
/// Kept separate from the popup's wiring so the popup can come and go
/// without touching settings state. Both bridges use the same
/// `codexbar` script-message handler name; they are different
/// `WebKitUserContentManager` instances, so nothing crosses over.
public final class SettingsWindow: @unchecked Sendable {
    private let window: GtkWindow
    private let webView: WebView
    private let bridge: Bridge
    private let coordinator: SettingsCoordinator

    public init(
        application: GtkApplication,
        coordinator: SettingsCoordinator,
        loginCoordinator: LoginCoordinator,
        registerSink: (@escaping @Sendable (SettingsPayload) -> Void) -> Void,
        onRefresh: @escaping @Sendable () -> Void,
        onQuit: @escaping @Sendable () -> Void)
    {
        self.coordinator = coordinator
        self.window = GtkWindow(
            application: application,
            title: "CodexBar Settings",
            width: 720,
            height: 640)
        self.webView = WebView()

        let coordinatorBox = coordinator
        self.bridge = Bridge(webView: self.webView) { command in
            let coordinator = coordinatorBox
            switch command {
            case .settingsReady:
                coordinator.republish()
            case let .updateProviderConfig(id, patch):
                do {
                    try coordinator.applyProviderPatch(id: id, patch: patch)
                } catch {
                    coordinator.reportError("Could not save provider settings: \(error)")
                }
            case let .updateSettings(settings):
                do {
                    try coordinator.applySettings(settings)
                } catch {
                    coordinator.reportError("Could not save settings: \(error)")
                }
            case let .updateHooks(hooks):
                do {
                    try coordinator.applyHooks(hooks)
                } catch {
                    coordinator.reportError("Could not save hooks: \(error)")
                }
            case let .replaceTokenAccounts(providerID, data):
                do {
                    try coordinator.replaceTokenAccounts(providerID: providerID, data: data)
                } catch {
                    coordinator.reportError("Could not save token accounts: \(error)")
                }
            case let .updateQuotaWarnings(providerID, warnings):
                do {
                    try coordinator.updateQuotaWarnings(providerID: providerID, config: warnings)
                } catch {
                    coordinator.reportError("Could not save quota warnings: \(error)")
                }
            case let .startLogin(providerID):
                guard let provider = UsageProvider(rawValue: providerID) else {
                    coordinator.reportError("Unknown provider: \(providerID)")
                    return
                }
                loginCoordinator.start(provider)
            case let .cancelLogin(providerID):
                guard let provider = UsageProvider(rawValue: providerID) else { return }
                loginCoordinator.cancel(provider)
            case .openConfigFolder:
                MainLoopDispatch.onMainLoop {
                    SystemBrowser.openPath(
                        CodexBarConfigStore.defaultURL().deletingLastPathComponent().path)
                }
            case let .openURL(url):
                MainLoopDispatch.onMainLoop { SystemBrowser.open(url) }
            case .refresh:
                onRefresh()
            case .quit:
                onQuit()
            case .ready, .selectProvider, .openSettings:
                break
            }
        }

        self.webView.loadBundledUI(page: "settings.html")
        self.window.setChild(self.webView.widgetPointer)
        self.window.setHideOnClose(true)
        registerSink { [weak self] payload in self?.bridge.send(.settings(payload)) }
        loginCoordinator.onPhase = { [weak self] provider, phase in
            self?.bridge.send(.loginProgress(
                provider: provider.rawValue,
                phase: LoginPhasePayload(phase)))
        }
        coordinator.onError = { [weak self] message in self?.bridge.send(.error(message: message)) }
    }

    public func present() {
        self.window.present()
    }

    public var isVisible: Bool {
        self.window.isVisible
    }
}

/// Opens an external URL without giving the web view network access.
public enum SystemBrowser {
    public static func open(_ url: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        process.arguments = [url]
        try? process.run()
    }

    public static func openPath(_ path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        process.arguments = [path]
        try? process.run()
    }
}
