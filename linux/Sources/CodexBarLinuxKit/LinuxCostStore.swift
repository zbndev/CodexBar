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
    private var generations: [String: UInt64] = [:]
    private var latestRequests: [String: Request] = [:]
    private var states: [String: ProviderCostState] = [:]

    public init(load: @escaping Loader) {
        self.load = load
    }

    public convenience init() {
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
        })
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
        self.lock.withLock {
            guard self.latestRequests[providerID] == request else { return }
            self.states[providerID] = state
        }
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
