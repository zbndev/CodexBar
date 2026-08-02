import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test
func `managed login writes only the isolated CODEX_HOME`() async throws {
    let fixture = try ManagedCodexFixture.make()
    let before = try Data(contentsOf: fixture.ambientAuth)
    _ = try await fixture.coordinator.add()
    #expect(try Data(contentsOf: fixture.ambientAuth) == before)
    #expect(FileManager.default.fileExists(atPath: fixture.managedAuth.path))
    #expect(try fixture.mode(of: fixture.managedAuth) == 0o600)
}

@Test func `adding the same provider identity updates the existing row`() async throws {
    let fixture = try ManagedCodexFixture.make()
    let first = try await fixture.coordinator.add()
    let secondCoordinator = fixture.makeCoordinator(identifier: UUID())
    let second = try await secondCoordinator.add()
    let accounts = try fixture.accounts()
    #expect(second.id == first.id)
    #expect(accounts.accounts.count == 1)
    #expect(accounts.account(id: first.id)?.managedHomePath == first.managedHomePath)
}

@Test func `reauthentication keeps the managed home and account id`() async throws {
    let fixture = try ManagedCodexFixture.make()
    let account = try await fixture.coordinator.add()
    let refreshed = try await fixture.coordinator.reauthenticate(id: account.id)
    #expect(refreshed.id == account.id)
    #expect(refreshed.managedHomePath == account.managedHomePath)
}

@Test func `removal deletes only the UUID managed home`() async throws {
    let fixture = try ManagedCodexFixture.make()
    let account = try await fixture.coordinator.add()
    let sibling = fixture.root.appendingPathComponent("sibling", isDirectory: true)
    try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
    try fixture.coordinator.remove(id: account.id)
    #expect(!FileManager.default.fileExists(atPath: account.managedHomePath))
    #expect(FileManager.default.fileExists(atPath: sibling.path))
}

private struct ManagedCodexFixture {
    let root: URL
    let ambientAuth: URL
    let managedAuth: URL
    let coordinator: LinuxManagedCodexAccountCoordinator

    private let tokenProvider: LinuxManagedCodexAccountCoordinator.TokenProvider

    static func make() throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-managed-\(UUID().uuidString)", isDirectory: true)
        let ambientHome = root.appendingPathComponent("ambient", isDirectory: true)
        let managedID = UUID()
        let managedHome = root
            .appendingPathComponent("managed-root", isDirectory: true)
            .appendingPathComponent(managedID.uuidString, isDirectory: true)
        let ambientAuth = ambientHome.appendingPathComponent("auth.json", isDirectory: false)
        let managedAuth = managedHome.appendingPathComponent("auth.json", isDirectory: false)
        try PrivateFileWriter.write(Data(#"{"token":"ambient-fixture"}"#.utf8), to: ambientAuth)
        try PrivateFileWriter.write(Data(#"{"token":"managed-fixture"}"#.utf8), to: managedAuth)

        let payload = try JSONSerialization.data(withJSONObject: [
            "email": "managed@example.test",
            "https://api.openai.com/auth": ["chatgpt_account_id": "acct-fixture"],
        ])
        let idToken = "fixture." + payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "") + ".signature"
        let tokenProvider: LinuxManagedCodexAccountCoordinator.TokenProvider = {
            OAuthTokens(
                accessToken: "managed-access-fixture",
                refreshToken: "managed-refresh-fixture",
                idToken: idToken,
                expiresIn: nil,
                scope: nil)
        }
        let coordinator = LinuxManagedCodexAccountCoordinator(
            rootURL: root.appendingPathComponent("managed-root", isDirectory: true),
            storeURL: root.appendingPathComponent("accounts.json", isDirectory: false),
            identifier: managedID,
            tokenProvider: tokenProvider)

        return Self(
            root: root,
            ambientAuth: ambientAuth,
            managedAuth: managedAuth,
            coordinator: coordinator,
            tokenProvider: tokenProvider)
    }

    func makeCoordinator(identifier: UUID) -> LinuxManagedCodexAccountCoordinator {
        LinuxManagedCodexAccountCoordinator(
            rootURL: self.root.appendingPathComponent("managed-root", isDirectory: true),
            storeURL: self.root.appendingPathComponent("accounts.json", isDirectory: false),
            identifier: identifier,
            tokenProvider: self.tokenProvider)
    }

    func accounts() throws -> ManagedCodexAccountSet {
        try FileManagedCodexAccountStore(
            fileURL: self.root.appendingPathComponent("accounts.json", isDirectory: false)).loadAccounts()
    }

    func mode(of url: URL) throws -> Int16 {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
            .flatMap { $0 as? NSNumber }?.int16Value ?? -1
    }
}
