import CodexBarCore
import Foundation

public struct ManagedCodexAccountView: Codable, Equatable, Sendable {
    public let id: UUID
    public let email: String
    public let workspaceLabel: String?
    public let isActive: Bool

    public init(id: UUID, email: String, workspaceLabel: String?, isActive: Bool) {
        self.id = id
        self.email = email
        self.workspaceLabel = workspaceLabel
        self.isActive = isActive
    }

    init(account: ManagedCodexAccount, isActive: Bool) {
        self.init(id: account.id, email: account.email, workspaceLabel: account.workspaceLabel, isActive: isActive)
    }
}

public enum LinuxManagedCodexAccountError: Error, Equatable, Sendable {
    case accountNotFound(UUID)
    case missingEmail
    case unsafeManagedHome(String)
}

public final class LinuxManagedCodexAccountCoordinator: @unchecked Sendable {
    public typealias TokenProvider = @Sendable () async throws -> OAuthTokens

    private let rootURL: URL
    private let storeURL: URL
    private let identifier: UUID?
    private let tokenProvider: TokenProvider
    private weak var settings: SettingsCoordinator?
    private let fileManager: FileManager

    public init(
        rootURL: URL = LinuxManagedCodexAccountCoordinator.defaultRootURL(),
        storeURL: URL? = nil,
        identifier: UUID? = nil,
        settings: SettingsCoordinator? = nil,
        tokenProvider: @escaping TokenProvider = LinuxManagedCodexAccountCoordinator.defaultTokenProvider,
        fileManager: FileManager = .default)
    {
        self.rootURL = rootURL.standardizedFileURL
        self.storeURL = (storeURL ?? Self.defaultStoreURL(rootURL: rootURL)).standardizedFileURL
        self.identifier = identifier
        self.settings = settings
        self.tokenProvider = tokenProvider
        self.fileManager = fileManager
    }

    public func add() async throws -> ManagedCodexAccount {
        let home = self.rootURL.appendingPathComponent(
            (self.identifier ?? UUID()).uuidString,
            isDirectory: true)
        let createdHome = !self.fileManager.fileExists(atPath: home.path)
        if createdHome {
            try self.fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        }
        do {
            return try await self.authenticate(home: home, existingID: nil)
        } catch {
            if createdHome {
                try? self.fileManager.removeItem(at: home)
            }
            throw error
        }
    }

    public func reauthenticate(id: UUID) async throws -> ManagedCodexAccount {
        let accounts = try self.loadAccounts()
        guard let account = accounts.account(id: id) else {
            throw LinuxManagedCodexAccountError.accountNotFound(id)
        }
        let home = URL(fileURLWithPath: account.managedHomePath, isDirectory: true)
        try self.validateManagedHome(home)
        try self.fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        return try await self.authenticate(home: home, existingID: id)
    }

    public func remove(id: UUID) throws {
        let accounts = try self.loadAccounts()
        guard let account = accounts.account(id: id) else { return }
        let home = URL(fileURLWithPath: account.managedHomePath, isDirectory: true)
        try self.validateManagedHome(home)
        if self.fileManager.fileExists(atPath: home.path) {
            try self.fileManager.removeItem(at: home)
        }
        try self.store(accounts.accounts.filter { $0.id != id })
        self.settings?.managedCodexAccountsDidChange()
    }

    public func select(id: UUID?) throws {
        try self.settings?.selectManagedCodexAccount(id: id)
    }

    public static func defaultRootURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let base = environment["XDG_CONFIG_HOME"].flatMap { path in
            path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(fileURLWithPath: path)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        return base
            .appendingPathComponent("codexbar", isDirectory: true)
            .appendingPathComponent("codex-accounts", isDirectory: true)
    }

    public static func defaultStoreURL(
        rootURL: URL = LinuxManagedCodexAccountCoordinator.defaultRootURL()) -> URL
    {
        rootURL.appendingPathComponent("accounts.json", isDirectory: false)
    }

    private func authenticate(home: URL, existingID: UUID?) async throws -> ManagedCodexAccount {
        let tokens = try await self.tokenProvider()
        try CodexLogin.save(tokens: tokens, environment: ["CODEX_HOME": home.path])
        let identity = UsageFetcher(environment: ["CODEX_HOME": home.path]).loadAuthBackedCodexAccount()
        guard let email = identity.email else { throw LinuxManagedCodexAccountError.missingEmail }

        let providerAccountID: String? = switch identity.identity {
        case let .providerAccount(id): id
        case .emailOnly, .unresolved: nil
        }
        let accounts = try self.loadAccounts()
        let existing = existingID.flatMap(accounts.account(id:))
            ?? accounts.account(email: email, providerAccountID: providerAccountID)
        let destination = existing.map { URL(fileURLWithPath: $0.managedHomePath, isDirectory: true) } ?? home

        if destination.standardizedFileURL != home.standardizedFileURL {
            try self.validateManagedHome(destination)
            let source = CodexAuthFingerprint.authFileURL(homePath: home.path)
            let target = CodexAuthFingerprint.authFileURL(homePath: destination.path)
            try PrivateFileWriter.write(Data(contentsOf: source), to: target)
            try self.fileManager.removeItem(at: home)
        }

        let now = Date().timeIntervalSince1970
        let account = ManagedCodexAccount(
            id: existing?.id ?? UUID(),
            email: email,
            providerAccountID: providerAccountID ?? existing?.providerAccountID,
            workspaceLabel: existing?.workspaceLabel,
            workspaceAccountID: existing?.workspaceAccountID,
            authFingerprint: CodexAuthFingerprint.fingerprint(homePath: destination.path, fileManager: self.fileManager),
            managedHomePath: destination.path,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            lastAuthenticatedAt: now)
        try self.store(accounts.accounts.filter { $0.id != account.id } + [account])
        self.settings?.managedCodexAccountsDidChange()
        return account
    }

    private func loadAccounts() throws -> ManagedCodexAccountSet {
        try FileManagedCodexAccountStore(fileURL: self.storeURL, fileManager: self.fileManager).loadAccounts()
    }

    private func store(_ accounts: [ManagedCodexAccount]) throws {
        let set = ManagedCodexAccountSet(version: FileManagedCodexAccountStore.currentVersion, accounts: accounts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try PrivateFileWriter.write(encoder.encode(set), to: self.storeURL)
    }

    private func validateManagedHome(_ home: URL) throws {
        let root = self.rootURL.standardizedFileURL
        let candidate = home.standardizedFileURL
        guard candidate.deletingLastPathComponent() == root,
              UUID(uuidString: candidate.lastPathComponent) != nil
        else {
            throw LinuxManagedCodexAccountError.unsafeManagedHome(home.path)
        }
    }

    public static func defaultTokenProvider() async throws -> OAuthTokens {
        let flow = OAuthLoginFlow(
            profile: CodexLogin.profile,
            openURL: { SystemBrowser.open($0) },
            progress: { _ in })
        return try await flow.run()
    }
}
