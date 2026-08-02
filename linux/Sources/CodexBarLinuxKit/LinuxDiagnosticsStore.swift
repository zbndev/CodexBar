import CodexBarCore
import Foundation

public struct LinuxDiagnosticAttempt: Codable, Equatable, Sendable {
    public let kind: String
    public let wasAvailable: Bool
    public let errorCategory: String?

    init(_ attempt: ProviderDiagnosticFetchAttempt) {
        self.kind = attempt.kind
        self.wasAvailable = attempt.wasAvailable
        self.errorCategory = attempt.errorCategory
    }
}

public struct LinuxDiagnosticSummary: Codable, Equatable, Sendable {
    public let provider: String
    public let source: String
    public let sourceMode: String
    public let appVersion: String?
    public let attempts: [LinuxDiagnosticAttempt]
    public let errorCategory: String?

    init(_ export: ProviderDiagnosticExport) {
        self.provider = export.provider
        self.source = export.source
        self.sourceMode = export.sourceMode
        self.appVersion = export.appVersion
        self.attempts = export.fetchAttempts.map(LinuxDiagnosticAttempt.init)
        self.errorCategory = export.error?.category
    }
}

public struct LinuxDiagnosticsPayload: Codable, Equatable, Sendable {
    public let diagnostics: [LinuxDiagnosticSummary]

    public init(diagnostics: [LinuxDiagnosticSummary]) {
        self.diagnostics = diagnostics
    }
}

public final class LinuxDiagnosticsStore: @unchecked Sendable {
    public struct Input: Sendable {
        public let provider: UsageProvider
        public let descriptor: ProviderDescriptor
        public let outcome: ProviderFetchOutcome
        public let sourceMode: ProviderSourceMode
        public let settings: ProviderSettingsSnapshot?
        public let auth: ProviderDiagnosticAuthSummary
        public let appVersion: String?

        public init(
            provider: UsageProvider,
            descriptor: ProviderDescriptor,
            outcome: ProviderFetchOutcome,
            sourceMode: ProviderSourceMode,
            settings: ProviderSettingsSnapshot?,
            auth: ProviderDiagnosticAuthSummary,
            appVersion: String?)
        {
            self.provider = provider
            self.descriptor = descriptor
            self.outcome = outcome
            self.sourceMode = sourceMode
            self.settings = settings
            self.auth = auth
            self.appVersion = appVersion
        }
    }

    private struct Entry {
        let export: ProviderDiagnosticExport
        let summary: LinuxDiagnosticSummary
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    public init() {}

    public func record(_ input: Input) {
        let export = ProviderDiagnosticExportBuilder.build(.init(
            provider: input.provider,
            descriptor: input.descriptor,
            outcome: input.outcome,
            sourceMode: input.sourceMode,
            settings: input.settings,
            auth: input.auth,
            appVersion: input.appVersion))
        self.lock.withLock {
            self.entries.append(Entry(export: export, summary: LinuxDiagnosticSummary(export)))
            if self.entries.count > 100 {
                self.entries.removeFirst(self.entries.count - 100)
            }
        }
    }

    public func payload() -> LinuxDiagnosticsPayload {
        self.lock.withLock { LinuxDiagnosticsPayload(diagnostics: self.entries.map(\.summary)) }
    }

    public func exportData() throws -> Data {
        let exports = self.lock.withLock { self.entries.map(\.export) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ProviderDiagnosticBatchExport(timestamp: Date(), diagnostics: exports))
    }
}
