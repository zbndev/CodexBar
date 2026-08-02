import CodexBarCore
import Foundation

public struct ProviderRefreshRecord: Sendable {
    public let view: ProviderView
    public let snapshot: UsageSnapshot?
    public let outcome: ProviderFetchOutcome

    public init(view: ProviderView, snapshot: UsageSnapshot?, outcome: ProviderFetchOutcome) {
        self.view = view
        self.snapshot = snapshot
        self.outcome = outcome
    }
}

public struct UtilizationHistoryPoint: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(capturedAt: Date, usedPercent: Double, resetsAt: Date?) {
        self.capturedAt = capturedAt
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct UtilizationHistorySegment: Codable, Equatable, Sendable {
    public let resetsAt: Date?
    public let points: [UtilizationHistoryPoint]

    public init(resetsAt: Date?, points: [UtilizationHistoryPoint]) {
        self.resetsAt = resetsAt
        self.points = points
    }
}

public struct UtilizationHistorySeries: Codable, Equatable, Sendable {
    public let windowID: String
    public let segments: [UtilizationHistorySegment]

    public init(windowID: String, segments: [UtilizationHistorySegment]) {
        self.windowID = windowID
        self.segments = segments
    }
}

public struct ProviderCostView: Codable, Equatable, Sendable {
    public let providerID: String
    public let sessionCostUSD: Double?
    public let last30DaysCostUSD: Double?
    public let currencyCode: String
    public let historyDays: Int
    public let daily: [CostUsageDailyReport.Entry]
    public let projects: [CostUsageProjectBreakdown]
    public let sessions: [CostUsageSessionBreakdown]
    public let updatedAt: Date
    public let source: String

    public init(
        providerID: String,
        sessionCostUSD: Double?,
        last30DaysCostUSD: Double?,
        currencyCode: String,
        historyDays: Int,
        daily: [CostUsageDailyReport.Entry],
        projects: [CostUsageProjectBreakdown],
        sessions: [CostUsageSessionBreakdown],
        updatedAt: Date,
        source: String)
    {
        self.providerID = providerID
        self.sessionCostUSD = sessionCostUSD
        self.last30DaysCostUSD = last30DaysCostUSD
        self.currencyCode = currencyCode
        self.historyDays = historyDays
        self.daily = daily
        self.projects = projects
        self.sessions = sessions
        self.updatedAt = updatedAt
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case providerID, sessionCostUSD, last30DaysCostUSD, currencyCode, historyDays
        case daily, projects, sessions, updatedAt, source
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providerID = try container.decode(String.self, forKey: .providerID)
        self.sessionCostUSD = try container.decodeIfPresent(Double.self, forKey: .sessionCostUSD)
        self.last30DaysCostUSD = try container.decodeIfPresent(Double.self, forKey: .last30DaysCostUSD)
        self.currencyCode = try container.decode(String.self, forKey: .currencyCode)
        self.historyDays = try container.decode(Int.self, forKey: .historyDays)
        self.daily = try container.decode([CostEntryPayload].self, forKey: .daily).map(\.value)
        self.projects = try container.decode([CostProjectPayload].self, forKey: .projects).map(\.value)
        self.sessions = try container.decode([CostSessionPayload].self, forKey: .sessions).map(\.value)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.source = try container.decode(String.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.providerID, forKey: .providerID)
        try container.encodeIfPresent(self.sessionCostUSD, forKey: .sessionCostUSD)
        try container.encodeIfPresent(self.last30DaysCostUSD, forKey: .last30DaysCostUSD)
        try container.encode(self.currencyCode, forKey: .currencyCode)
        try container.encode(self.historyDays, forKey: .historyDays)
        try container.encode(self.daily.map(CostEntryPayload.init), forKey: .daily)
        try container.encode(self.projects.map(CostProjectPayload.init), forKey: .projects)
        try container.encode(self.sessions.map(CostSessionPayload.init), forKey: .sessions)
        try container.encode(self.updatedAt, forKey: .updatedAt)
        try container.encode(self.source, forKey: .source)
    }

    /// The same snapshot minus everything that names the user's work: project
    /// paths and session ids. Totals and the daily report carry no identity.
    public func hidingPersonalInfo() -> ProviderCostView {
        ProviderCostView(
            providerID: self.providerID,
            sessionCostUSD: self.sessionCostUSD,
            last30DaysCostUSD: self.last30DaysCostUSD,
            currencyCode: self.currencyCode,
            historyDays: self.historyDays,
            daily: self.daily,
            projects: [],
            sessions: [],
            updatedAt: self.updatedAt,
            source: self.source)
    }
}

private struct CostModelPayload: Codable {
    let modelName: String
    let costUSD: Double?
    let totalTokens: Int?
    let requestCount: Int?
    let standardCostUSD: Double?
    let priorityCostUSD: Double?
    let standardTokens: Int?
    let priorityTokens: Int?

    init(_ value: CostUsageDailyReport.ModelBreakdown) {
        self.modelName = value.modelName
        self.costUSD = value.costUSD
        self.totalTokens = value.totalTokens
        self.requestCount = value.requestCount
        self.standardCostUSD = value.standardCostUSD
        self.priorityCostUSD = value.priorityCostUSD
        self.standardTokens = value.standardTokens
        self.priorityTokens = value.priorityTokens
    }

    var value: CostUsageDailyReport.ModelBreakdown {
        CostUsageDailyReport.ModelBreakdown(
            modelName: self.modelName,
            costUSD: self.costUSD,
            totalTokens: self.totalTokens,
            requestCount: self.requestCount,
            standardCostUSD: self.standardCostUSD,
            priorityCostUSD: self.priorityCostUSD,
            standardTokens: self.standardTokens,
            priorityTokens: self.priorityTokens)
    }
}

private struct CostEntryPayload: Codable {
    let date: String
    let inputTokens: Int?
    let cacheReadTokens: Int?
    let cacheCreationTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let requestCount: Int?
    let costUSD: Double?
    let modelsUsed: [String]?
    let modelBreakdowns: [CostModelPayload]?

    init(_ value: CostUsageDailyReport.Entry) {
        self.date = value.date
        self.inputTokens = value.inputTokens
        self.cacheReadTokens = value.cacheReadTokens
        self.cacheCreationTokens = value.cacheCreationTokens
        self.outputTokens = value.outputTokens
        self.totalTokens = value.totalTokens
        self.requestCount = value.requestCount
        self.costUSD = value.costUSD
        self.modelsUsed = value.modelsUsed
        self.modelBreakdowns = value.modelBreakdowns?.map(CostModelPayload.init)
    }

    var value: CostUsageDailyReport.Entry {
        CostUsageDailyReport.Entry(
            date: self.date,
            inputTokens: self.inputTokens,
            outputTokens: self.outputTokens,
            cacheReadTokens: self.cacheReadTokens,
            cacheCreationTokens: self.cacheCreationTokens,
            totalTokens: self.totalTokens,
            requestCount: self.requestCount,
            costUSD: self.costUSD,
            modelsUsed: self.modelsUsed,
            modelBreakdowns: self.modelBreakdowns?.map(\.value))
    }
}

private struct CostSourcePayload: Codable {
    let name: String
    let path: String?
    let totalTokens: Int?
    let totalCostUSD: Double?
    let daily: [CostEntryPayload]
    let modelBreakdowns: [CostModelPayload]?

    init(_ value: CostUsageProjectSourceBreakdown) {
        self.name = value.name
        self.path = value.path
        self.totalTokens = value.totalTokens
        self.totalCostUSD = value.totalCostUSD
        self.daily = value.daily.map(CostEntryPayload.init)
        self.modelBreakdowns = value.modelBreakdowns?.map(CostModelPayload.init)
    }

    var value: CostUsageProjectSourceBreakdown {
        CostUsageProjectSourceBreakdown(
            name: self.name,
            path: self.path,
            totalTokens: self.totalTokens,
            totalCostUSD: self.totalCostUSD,
            daily: self.daily.map(\.value),
            modelBreakdowns: self.modelBreakdowns?.map(\.value))
    }
}

private struct CostProjectPayload: Codable {
    let name: String
    let path: String?
    let totalTokens: Int?
    let totalCostUSD: Double?
    let daily: [CostEntryPayload]
    let modelBreakdowns: [CostModelPayload]?
    let sources: [CostSourcePayload]

    init(_ value: CostUsageProjectBreakdown) {
        self.name = value.name
        self.path = value.path
        self.totalTokens = value.totalTokens
        self.totalCostUSD = value.totalCostUSD
        self.daily = value.daily.map(CostEntryPayload.init)
        self.modelBreakdowns = value.modelBreakdowns?.map(CostModelPayload.init)
        self.sources = value.sources.map(CostSourcePayload.init)
    }

    var value: CostUsageProjectBreakdown {
        CostUsageProjectBreakdown(
            name: self.name,
            path: self.path,
            totalTokens: self.totalTokens,
            totalCostUSD: self.totalCostUSD,
            daily: self.daily.map(\.value),
            modelBreakdowns: self.modelBreakdowns?.map(\.value),
            sources: self.sources.map(\.value))
    }
}

private struct CostSessionPayload: Codable {
    let sessionID: String
    let lastActivity: Date
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let requestCount: Int?
    let costUSD: Double?
    let modelBreakdowns: [CostModelPayload]

    init(_ value: CostUsageSessionBreakdown) {
        self.sessionID = value.sessionID
        self.lastActivity = value.lastActivity
        self.inputTokens = value.inputTokens
        self.cachedInputTokens = value.cachedInputTokens
        self.outputTokens = value.outputTokens
        self.totalTokens = value.totalTokens
        self.requestCount = value.requestCount
        self.costUSD = value.costUSD
        self.modelBreakdowns = value.modelBreakdowns.map(CostModelPayload.init)
    }

    var value: CostUsageSessionBreakdown {
        CostUsageSessionBreakdown(
            sessionID: self.sessionID,
            lastActivity: self.lastActivity,
            inputTokens: self.inputTokens,
            cachedInputTokens: self.cachedInputTokens,
            outputTokens: self.outputTokens,
            totalTokens: self.totalTokens,
            requestCount: self.requestCount,
            costUSD: self.costUSD,
            modelBreakdowns: self.modelBreakdowns.map(\.value))
    }
}
