import CodexBarCore
import Crypto
import Foundation

public enum ProviderCostState: Codable, Equatable, Sendable {
    case unavailable
    case available(ProviderCostView)
}

public struct CostUsageLoadRequest: Sendable {
    public let provider: UsageProvider
    public let config: ProviderConfig
    public let forceRefresh: Bool
    public let historyDays: Int

    public init(provider: UsageProvider, config: ProviderConfig, forceRefresh: Bool, historyDays: Int) {
        self.provider = provider
        self.config = config
        self.forceRefresh = forceRefresh
        self.historyDays = historyDays
    }
}

public final class LinuxCostStore: @unchecked Sendable {
    public typealias Loader = @Sendable (CostUsageLoadRequest) async throws -> CostUsageTokenSnapshot

    private struct Request: Equatable {
        let key: String
        let generation: UInt64
    }

    private let lock = NSLock()
    private let load: Loader
    /// Fires after a refresh actually publishes a new state (stale-generation
    /// discards excluded), so the popup and the spend pane can republish with
    /// the fresh snapshot. Invoked outside the lock.
    private let onChange: @Sendable () -> Void
    private var generations: [String: UInt64] = [:]
    private var latestRequests: [String: Request] = [:]
    private var states: [String: ProviderCostState] = [:]

    public init(load: @escaping Loader, onChange: @escaping @Sendable () -> Void = {}) {
        self.load = load
        self.onChange = onChange
    }

    public convenience init(onChange: @escaping @Sendable () -> Void = {}) {
        self.init(load: { request in
            let environment = UsageRefresher.resolvedEnvironment(
                base: ProcessInfo.processInfo.environment,
                provider: request.provider,
                config: request.config)
            return try await CostUsageFetcher().loadTokenSnapshot(
                provider: request.provider,
                environment: environment,
                forceRefresh: request.forceRefresh,
                historyDays: request.historyDays)
        }, onChange: onChange)
    }

    public func refresh(providerID: String, config: ProviderConfig, forceRefresh: Bool = false) async {
        guard config.enabled == true, config.id.rawValue == providerID else {
            self.lock.withLock { self.states[providerID] = .unavailable }
            return
        }
        guard Self.supports(config.id) else {
            self.lock.withLock { self.states[providerID] = .unavailable }
            return
        }
        let request = self.startRequest(providerID: providerID, config: config)
        do {
            let snapshot = try await self.load(CostUsageLoadRequest(
                provider: config.id,
                config: config,
                forceRefresh: forceRefresh,
                historyDays: 30))
            let view = ProviderCostView(
                providerID: providerID,
                sessionCostUSD: snapshot.sessionCostUSD,
                last30DaysCostUSD: snapshot.last30DaysCostUSD,
                currencyCode: snapshot.currencyCode,
                historyDays: snapshot.historyDays,
                daily: snapshot.daily,
                projects: snapshot.projects,
                sessions: snapshot.sessions,
                updatedAt: snapshot.updatedAt,
                source: "Local estimate")
            self.publish(.available(view), providerID: providerID, request: request)
        } catch is CostUsageError {
            self.publish(.unavailable, providerID: providerID, request: request)
        } catch {
            self.publish(.unavailable, providerID: providerID, request: request)
        }
    }

    public func state(providerID: String) -> ProviderCostState? {
        self.lock.withLock { self.states[providerID] }
    }

    public func view(providerID: String) -> ProviderCostView? {
        guard case let .available(view)? = self.state(providerID: providerID) else { return nil }
        return view
    }

    /// Every provider with an available snapshot, in stable id order — the
    /// spend pane's data source.
    public func availableViews() -> [ProviderCostView] {
        self.lock.withLock {
            self.states.values.compactMap { state -> ProviderCostView? in
                guard case let .available(view) = state else { return nil }
                return view
            }.sorted { $0.providerID < $1.providerID }
        }
    }

    private func startRequest(providerID: String, config: ProviderConfig) -> Request {
        self.lock.withLock {
            let key = "\(providerID):\(Self.fingerprint(config))"
            let generation = self.generations[key, default: 0] + 1
            self.generations[key] = generation
            let request = Request(key: key, generation: generation)
            self.latestRequests[providerID] = request
            return request
        }
    }

    private func publish(_ state: ProviderCostState, providerID: String, request: Request) {
        // The lock is not reentrant and onChange republishes through stores
        // that read this one, so the callback must run after it is released.
        let published = self.lock.withLock { () -> Bool in
            guard self.latestRequests[providerID] == request else { return false }
            self.states[providerID] = state
            return true
        }
        if published { self.onChange() }
    }

    private static func fingerprint(_ config: ProviderConfig) -> String {
        let data = (try? JSONEncoder().encode(config)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func supports(_ provider: UsageProvider) -> Bool {
        switch provider {
        case .codex, .claude, .vertexai, .bedrock:
            true
        case .cursor:
            #if os(macOS)
            true
            #else
            false
            #endif
        default:
            false
        }
    }
}
