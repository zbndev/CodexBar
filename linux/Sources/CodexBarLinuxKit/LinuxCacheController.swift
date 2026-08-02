import CodexBarCore
import Foundation

public struct CacheClearResult: Codable, Equatable, Sendable {
    public let clearedCount: Int
    public let failedCount: Int

    public init(clearedCount: Int, failedCount: Int) {
        self.clearedCount = clearedCount
        self.failedCount = failedCount
    }
}

public struct LinuxStorageScanRequest: Sendable {
    public let provider: UsageProvider
    public let paths: [String]

    public init(provider: UsageProvider, paths: [String]) {
        self.provider = provider
        self.paths = paths
    }
}

public struct StorageRecommendation: Codable, Equatable, Sendable {
    public let title: String
    public let consequence: String

    public init(title: String, consequence: String) {
        self.title = title
        self.consequence = consequence
    }
}

public struct LinuxStorageFootprint: Codable, Equatable, Sendable {
    public let providerID: String
    public let totalBytes: Int64
    public let recommendations: [StorageRecommendation]

    public init(providerID: String, totalBytes: Int64, recommendations: [StorageRecommendation]) {
        self.providerID = providerID
        self.totalBytes = totalBytes
        self.recommendations = recommendations
    }
}

public struct LinuxStorageFootprintsPayload: Codable, Equatable, Sendable {
    public let footprints: [LinuxStorageFootprint]

    public init(footprints: [LinuxStorageFootprint]) {
        self.footprints = footprints
    }
}

public struct LinuxCachePayload: Codable, Equatable, Sendable {
    public let costCache: CacheClearResult?
    public let cookieCache: CacheClearResult?
    public let storage: LinuxStorageFootprintsPayload

    public init(
        costCache: CacheClearResult? = nil,
        cookieCache: CacheClearResult? = nil,
        storage: LinuxStorageFootprintsPayload = LinuxStorageFootprintsPayload(footprints: []))
    {
        self.costCache = costCache
        self.cookieCache = cookieCache
        self.storage = storage
    }
}

public final class LinuxCacheController: @unchecked Sendable {
    public typealias CostCacheClear = @Sendable () async -> CacheClearResult
    public typealias CookieCacheClear = @Sendable () -> CacheClearResult

    private let clearCost: CostCacheClear
    private let clearCookies: CookieCacheClear
    private let scanner: ProviderStorageScanner
    private let lock = NSLock()
    private var latestCostResult: CacheClearResult?
    private var latestCookieResult: CacheClearResult?
    private var latestStorage = LinuxStorageFootprintsPayload(footprints: [])

    public init(
        clearCostCache: CostCacheClear? = nil,
        clearCookieCache: CookieCacheClear? = nil,
        scanner: ProviderStorageScanner = ProviderStorageScanner())
    {
        self.clearCost = clearCostCache ?? Self.clearCoreCostCache
        self.clearCookies = clearCookieCache ?? Self.clearCoreCookieCache
        self.scanner = scanner
    }

    public func clearCostCache() async -> CacheClearResult {
        let result = await self.clearCost()
        self.lock.withLock { self.latestCostResult = result }
        return result
    }

    public func clearCookieCache() -> CacheClearResult {
        let result = self.clearCookies()
        self.lock.withLock { self.latestCookieResult = result }
        return result
    }

    public func refreshStorageFootprints(_ requests: [LinuxStorageScanRequest]) -> LinuxStorageFootprintsPayload {
        let payload = LinuxStorageFootprintsPayload(footprints: requests.map { request in
            let footprint = self.scanner.scan(provider: request.provider, candidatePaths: request.paths)
            return LinuxStorageFootprint(
                providerID: request.provider.rawValue,
                totalBytes: footprint.totalBytes,
                recommendations: footprint.cleanupRecommendations.map {
                    StorageRecommendation(title: $0.title, consequence: $0.consequence)
                })
        })
        self.lock.withLock { self.latestStorage = payload }
        return payload
    }

    public func payload() -> LinuxCachePayload {
        self.lock.withLock {
            LinuxCachePayload(
                costCache: self.latestCostResult,
                cookieCache: self.latestCookieResult,
                storage: self.latestStorage)
        }
    }

    private static func clearCoreCostCache() async -> CacheClearResult {
        await CostUsageFetcher().clearCachedCodexLocalProjectUsageSnapshot()
        return CacheClearResult(clearedCount: 1, failedCount: 0)
    }

    private static func clearCoreCookieCache() -> CacheClearResult {
        let summary = CookieHeaderCache.clearAllDetailed()
        return CacheClearResult(clearedCount: summary.clearedCount, failedCount: summary.failedCount)
    }
}
