import Foundation

public final class LinuxPlanHistoryStore: @unchecked Sendable {
    private static let sampleInterval: TimeInterval = 60
    private static let retention: TimeInterval = 90 * 86_400

    private let directoryURL: URL
    private let lock = NSLock()
    private let now: @Sendable () -> Date

    public init(
        directoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/codexbar/history", isDirectory: true),
        now: @escaping @Sendable () -> Date = Date.init) throws
    {
        self.directoryURL = directoryURL
        self.now = now
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    public func record(providerID: String, windowID: String, point: UtilizationHistoryPoint) throws {
        guard point.usedPercent.isFinite, !windowID.isEmpty else { return }
        try self.lock.withLock {
            var series = try self.loadLocked(providerID: providerID, windowID: windowID)
            let cutoff = self.now().addingTimeInterval(-Self.retention)
            var segments = series.segments.map { segment in
                UtilizationHistorySegment(
                    resetsAt: segment.resetsAt,
                    points: segment.points.filter { $0.capturedAt >= cutoff })
            }.filter { !$0.points.isEmpty }

            if let last = segments.popLast() {
                if last.resetsAt == point.resetsAt {
                    var points = last.points
                    if let lastPoint = last.points.last,
                       point.capturedAt.timeIntervalSince(lastPoint.capturedAt) < Self.sampleInterval
                    {
                        points[points.count - 1] = point
                    } else {
                        points.append(point)
                    }
                    segments.append(UtilizationHistorySegment(resetsAt: last.resetsAt, points: points))
                } else {
                    segments.append(last)
                    segments.append(UtilizationHistorySegment(resetsAt: point.resetsAt, points: [point]))
                }
            } else {
                segments.append(UtilizationHistorySegment(resetsAt: point.resetsAt, points: [point]))
            }
            series = UtilizationHistorySeries(windowID: windowID, segments: segments)
            try self.saveLocked(series, providerID: providerID)
        }
    }

    public func load(providerID: String, windowID: String) throws -> UtilizationHistorySeries {
        try self.lock.withLock {
            try self.loadLocked(providerID: providerID, windowID: windowID)
        }
    }

    private func loadLocked(providerID: String, windowID: String) throws -> UtilizationHistorySeries {
        let url = try self.fileURL(providerID: providerID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return UtilizationHistorySeries(windowID: windowID, segments: [])
        }
        let stored = try JSONDecoder().decode([String: UtilizationHistorySeries].self, from: Data(contentsOf: url))
        return stored[windowID] ?? UtilizationHistorySeries(windowID: windowID, segments: [])
    }

    private func saveLocked(_ series: UtilizationHistorySeries, providerID: String) throws {
        let url = try self.fileURL(providerID: providerID)
        var stored: [String: UtilizationHistorySeries] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            stored = try JSONDecoder().decode([String: UtilizationHistorySeries].self, from: Data(contentsOf: url))
        }
        stored[series.windowID] = series
        try PrivateFileWriter.write(JSONEncoder().encode(stored), to: url)
    }

    private func fileURL(providerID: String) throws -> URL {
        guard !providerID.isEmpty,
              providerID == URL(fileURLWithPath: providerID).lastPathComponent,
              !providerID.contains("/")
        else {
            throw CocoaError(.fileNoSuchFile)
        }
        return self.directoryURL.appendingPathComponent("\(providerID).json", isDirectory: false)
    }
}
