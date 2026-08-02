import CodexBarCore
import Crypto
import Foundation

public enum ProviderCostState: Codable, Equatable, Sendable {
    case unavailable
    case available(ProviderCostView)
}

public final class LinuxCostStore: @unchecked Sendable {
    public typealias Loader = @Sendable (UsageProvider, ProviderConfig, Bool) async throws -> CostUsageTokenSnapshot

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

    public func refresh(providerID: String, config: ProviderConfig, forceRefresh: Bool = false) async {
        guard config.enabled == true, config.id.rawValue == providerID else {
            self.lock.withLock { self.states[providerID] = .unavailable }
            return
        }
        let request = self.startRequest(providerID: providerID, config: config)
        do {
            let snapshot = try await self.load(config.id, config, forceRefresh)
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
}
