import CodexBarCore
import Foundation

/// Owns every running login. The settings window starts and cancels flows
/// through here; progress travels back as `LoginPhase` and the window encodes
/// it into a `BridgeEvent`.
///
/// Secrets never pass through this type's callbacks: phases carry display
/// values only. Tokens and cookie headers go from the flow straight into the
/// provider's store.
///
/// Threading: `start`/`cancel` are called on the main loop (from the bridge
/// handler). Flow progress arrives on arbitrary task threads and hops to the
/// main loop before touching the callbacks or the bookkeeping dictionaries.
public final class LoginCoordinator: @unchecked Sendable {
    private let application: GtkApplication
    private let settings: SettingsCoordinator

    /// Set by SettingsWindow once its bridge exists. Called on the main loop.
    public var onPhase: (@Sendable (UsageProvider, LoginPhase) -> Void)?
    /// Fires after credentials are durably stored — main.swift sets it to
    /// republish settings and refresh usage. Called on the main loop.
    public var onFinish: (@Sendable (UsageProvider) -> Void)?

    private var activeTasks: [UsageProvider: Task<Void, Never>] = [:]
    private var cookieWindows: [UsageProvider: CookieLoginWindow] = [:]
    private var externalProcesses: [UsageProvider: any ExternalProcessHandle] = [:]

    public init(application: GtkApplication, settings: SettingsCoordinator) {
        self.application = application
        self.settings = settings
    }

    /// Idempotent per provider: a second click while a login runs is ignored.
    public func start(_ provider: UsageProvider) {
        guard self.activeTasks[provider] == nil, self.cookieWindows[provider] == nil else { return }
        guard let route = LoginCatalog.route(for: provider) else { return }

        switch route {
        case let .oauth(profile, _, save):
            self.startOAuth(provider: provider, profile: profile, save: save)
        case .deviceFlow:
            self.startDeviceFlow(provider: provider)
        case let .embeddedCookie(entry):
            self.startCookieLogin(provider: provider, entry: entry)
        case let .externalCredential(entry):
            self.startExternalCredentialLogin(provider: provider, entry: entry)
        }
    }

    /// Unblocks the UI immediately. OAuth listeners observe cancellation
    /// (`LoopbackCallbackServer.waitForRequest`); the device flow may poll on
    /// in the background — its late result is dropped because the provider is
    /// no longer in `activeTasks`.
    public func cancel(_ provider: UsageProvider) {
        self.activeTasks.removeValue(forKey: provider)?.cancel()
        self.externalProcesses.removeValue(forKey: provider)?.terminate()
        // A cookie window cancelled from the settings UI is marked dead; its
        // late "Save session" is dropped by the guard in the onFinish closure.
        self.cookieWindows.removeValue(forKey: provider)
        self.report(provider, .failed(message: LoginError.cancelled.message))
    }

    public func cancelAll() {
        let providers = Set(self.activeTasks.keys)
            .union(self.cookieWindows.keys)
            .union(self.externalProcesses.keys)
        for provider in providers {
            self.cancel(provider)
        }
    }

    // MARK: - Official external credential tools

    private func startExternalCredentialLogin(provider: UsageProvider, entry: ExternalCredentialLoginEntry) {
        let task = Task { [weak self] in
            guard let self else { return }
            let initialReadiness = await entry.readiness()
            do {
                try Task.checkCancellation()
                switch initialReadiness {
                case .ready:
                    self.complete(provider)
                case let .unavailable(executable):
                    self.report(provider, .waitingForExternalTool(
                        command: executable,
                        helpURL: entry.helpURL.absoluteString))
                    self.stopExternalLogin(provider)
                case .waiting:
                    let process = try SystemTerminal.launch(
                        executable: entry.executableCandidates[0],
                        arguments: entry.arguments)
                    MainLoopDispatch.onMainLoop {
                        guard self.activeTasks[provider] != nil else {
                            process.terminate()
                            return
                        }
                        self.externalProcesses[provider] = process
                    }
                    self.report(provider, .waitingForExternalTool(
                        command: entry.command,
                        helpURL: entry.helpURL.absoluteString))
                    try await self.waitForExternalCredential(entry: entry)
                    self.complete(provider)
            }
            } catch is CancellationError {
            } catch {
                self.fail(provider, message: error.localizedDescription)
            }
        }
        self.activeTasks[provider] = task
    }

    private func waitForExternalCredential(entry: ExternalCredentialLoginEntry) async throws {
        let deadline = Date().addingTimeInterval(600)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            try await Task.sleep(for: .seconds(min(1, remaining)))
            if await entry.readiness() == .ready {
                return
            }
        }
        throw ExternalCredentialLoginError.timedOut
    }

    private func stopExternalLogin(_ provider: UsageProvider) {
        MainLoopDispatch.onMainLoop {
            self.activeTasks.removeValue(forKey: provider)
        }
    }

    // MARK: - OAuth (Claude, Codex)

    private func startOAuth(
        provider: UsageProvider,
        profile: OAuthProviderProfile,
        save: @escaping @Sendable (OAuthTokens) throws -> Void)
    {
        let task = Task { [weak self] in
            guard let self else { return }
            let flow = OAuthLoginFlow(
                profile: profile,
                openURL: { SystemBrowser.open($0) },
                progress: { [weak self] phase in self?.report(provider, phase) })
            do {
                let tokens = try await flow.run()
                try Task.checkCancellation()
                self.report(provider, .saving)
                try save(tokens)
                self.complete(provider)
            } catch is CancellationError {
                // cancel(_:) already reported.
            } catch let error as LoginError {
                self.fail(provider, message: error.message)
            } catch {
                self.fail(provider, message: error.localizedDescription)
            }
        }
        self.activeTasks[provider] = task
    }

    // MARK: - Device flow (Copilot)

    private func startDeviceFlow(provider: UsageProvider) {
        let task = Task { [weak self] in
            guard let self else { return }
            let config = self.settings.providerConfig(id: provider.rawValue)
            do {
                let data = try await CopilotLogin.run(
                    enterpriseHost: config?.enterpriseHost,
                    existing: config?.tokenAccounts,
                    openURL: { SystemBrowser.open($0) },
                    progress: { [weak self] phase in
                        // CopilotLogin.run reports `.finished` when polling
                        // succeeds; hold it back until the accounts persist.
                        guard phase != .finished else { return }
                        self?.report(provider, phase)
                    })
                try Task.checkCancellation()
                self.report(provider, .saving)
                try self.settings.replaceTokenAccounts(providerID: provider.rawValue, data: data)
                self.complete(provider)
            } catch is CancellationError {
            } catch let error as LoginError {
                self.fail(provider, message: error.message)
            } catch {
                self.fail(provider, message: error.localizedDescription)
            }
        }
        self.activeTasks[provider] = task
    }

    // MARK: - Embedded cookie login (the 30 web providers)

    private func startCookieLogin(provider: UsageProvider, entry: CookieLoginEntry) {
        let name = ProviderDescriptorRegistry.all
            .first { $0.id == provider }?.metadata.displayName ?? provider.rawValue
        let window = CookieLoginWindow(
            application: self.application,
            providerName: name,
            entry: entry) { [weak self] header in
                guard let self else { return }
                // A provider cancelled from the settings UI was removed from
                // the map already; its late harvest is dropped.
                guard self.cookieWindows.removeValue(forKey: provider) != nil else { return }
                guard let header else {
                    self.report(provider, .failed(message: LoginError.cancelled.message))
                    return
                }
                do {
                    var patch = ProviderConfigPatch()
                    patch.cookieSource = .manual
                    patch.cookieHeader = header
                    try self.settings.applyProviderPatch(id: provider.rawValue, patch: patch)
                    self.complete(provider)
                } catch {
                    self.fail(provider, message: error.localizedDescription)
                }
            }
        self.cookieWindows[provider] = window
        self.report(provider, .waitingForBrowser(url: entry.loginURL))
        window.present()
    }

    // MARK: - Reporting

    private func complete(_ provider: UsageProvider) {
        MainLoopDispatch.onMainLoop {
            self.activeTasks.removeValue(forKey: provider)
            self.externalProcesses.removeValue(forKey: provider)
            self.onPhase?(provider, .finished)
            self.onFinish?(provider)
        }
    }

    private func fail(_ provider: UsageProvider, message: String) {
        MainLoopDispatch.onMainLoop {
            self.activeTasks.removeValue(forKey: provider)
            self.externalProcesses.removeValue(forKey: provider)
            self.onPhase?(provider, .failed(message: message))
        }
    }

    private func report(_ provider: UsageProvider, _ phase: LoginPhase) {
        MainLoopDispatch.onMainLoop {
            self.onPhase?(provider, phase)
        }
    }
}

private enum ExternalCredentialLoginError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "Sign-in did not complete within 10 minutes."
        }
    }
}
