import CodexBarCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ProviderStatusRequest: Equatable, Sendable {
    public let url: URL
    public let timeout: Duration
    public let headers: [String: String]

    public init(url: URL, timeout: Duration, headers: [String: String] = [:]) {
        self.url = url
        self.timeout = timeout
        self.headers = headers
    }
}

public enum ProviderStatusTransition: Equatable, Sendable {
    case unavailable(providerID: String)
    case recovered(providerID: String)
}

public final class ProviderStatusPoller: @unchecked Sendable {
    public typealias Transport = @Sendable (ProviderStatusRequest) async -> Int?

    public let cadence: Duration = .seconds(10 * 60)
    private let descriptors: [ProviderDescriptor]
    private let statusChecksEnabled: @Sendable () -> Bool
    private let transport: Transport
    private let onTransition: @Sendable (ProviderStatusTransition) -> Void
    private let lock = NSLock()
    private var unavailableProviderIDs: Set<String> = []
    private var task: Task<Void, Never>?

    public init(
        descriptors: [ProviderDescriptor] = ProviderDescriptorRegistry.all,
        statusChecksEnabled: @escaping @Sendable () -> Bool,
        transport: Transport? = nil,
        onTransition: @escaping @Sendable (ProviderStatusTransition) -> Void = { _ in })
    {
        self.descriptors = descriptors
        self.statusChecksEnabled = statusChecksEnabled
        self.transport = transport ?? Self.networkStatus
        self.onTransition = onTransition
    }

    public var isRunning: Bool {
        self.lock.withLock { self.task != nil }
    }

    public func start() {
        guard self.statusChecksEnabled() else { return }
        let shouldStart = self.lock.withLock { () -> Bool in
            guard self.task == nil else { return false }
            self.task = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    await self.pollOnce()
                    guard self.statusChecksEnabled(), !Task.isCancelled else { break }
                    do {
                        try await Task.sleep(for: self.cadence)
                    } catch {
                        break
                    }
                }
                self.lock.withLock { self.task = nil }
            }
            return true
        }
        if !shouldStart { return }
    }

    public func stop() {
        let task = self.lock.withLock { () -> Task<Void, Never>? in
            defer { self.task = nil }
            return self.task
        }
        task?.cancel()
    }

    public func pollOnce() async {
        guard self.statusChecksEnabled() else {
            self.stop()
            return
        }
        for descriptor in self.descriptors {
            guard let string = descriptor.metadata.statusPageURL, let url = URL(string: string) else { continue }
            let code = await self.transport(ProviderStatusRequest(url: url, timeout: .seconds(10)))
            let isAvailable = code.map { 200 ..< 300 ~= $0 } ?? false
            let transition = self.lock.withLock { () -> ProviderStatusTransition? in
                if isAvailable {
                    return self.unavailableProviderIDs.remove(descriptor.id.rawValue) == nil
                        ? nil
                        : .recovered(providerID: descriptor.id.rawValue)
                }
                return self.unavailableProviderIDs.insert(descriptor.id.rawValue).inserted
                    ? .unavailable(providerID: descriptor.id.rawValue)
                    : nil
            }
            if let transition, self.statusChecksEnabled() {
                self.onTransition(transition)
            }
        }
    }

    private static func networkStatus(_ request: ProviderStatusRequest) async -> Int? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        var urlRequest = URLRequest(url: request.url)
        urlRequest.timeoutInterval = 10
        urlRequest.httpShouldHandleCookies = false
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        do {
            let (_, response) = try await session.data(for: urlRequest)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }
}
