import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test
func `organization refresh deduplicates ids and preserves valid selections`() async throws {
    let coordinator = KiloOrganizationCoordinator(fetch: {
        [KiloOrganization(id: "a", name: "A", role: nil),
         KiloOrganization(id: "a", name: "A renamed", role: "admin"),
         KiloOrganization(id: "b", name: "B", role: nil)]
    })
    let result = try await coordinator.refresh(previousEnabledIDs: ["a", "gone"])
    #expect(result.organizations.map(\.id) == ["a", "b"])
    #expect(result.enabledIDs == ["a"])
}

@Test
func `organization discovery persists the normalized list and selections together`() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let configStore = CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
    try configStore.save(CodexBarConfig(providers: [ProviderConfig(
        id: .kilo,
        enabled: true,
        source: .api,
        apiKey: "fixture-key",
        kiloKnownOrganizations: [KiloOrganization(id: "old", name: "Old", role: nil)],
        kiloEnabledOrganizationIDs: ["a", "gone"])]))
    let state = KiloOrganizationsState()
    let coordinator = SettingsCoordinator(
        configStore: configStore,
        settingsStore: LinuxSettingsStore(fileURL: directory.appendingPathComponent("settings.json")),
        kiloOrganizations: state,
        kiloOrganizationFetch: { _, _ in
            [KiloOrganization(id: "a", name: "A", role: nil),
             KiloOrganization(id: "a", name: "A renamed", role: "admin"),
             KiloOrganization(id: "b", name: "B", role: nil)]
        },
        onChange: {})

    await coordinator.refreshKiloOrganizations()

    let stored = try #require(try configStore.load()?.providerConfig(for: .kilo))
    let organizations = stored.kiloKnownOrganizations ?? []
    #expect(organizations.map(\.id) == ["a", "b"])
    #expect(organizations.first?.name == "A renamed")
    #expect(stored.kiloEnabledOrganizationIDs == ["a"])
    #expect(state.payload().enabledIDs == ["a"])
}

@Test
func `scope fan-out retains successful scopes when an organization fails`() async {
    let scopes: [KiloUsageScope] = [
        .personal,
        .organization(id: "fixture-org", name: "Fixture Organization"),
    ]
    let results = await KiloOrganizationCoordinator.refreshScopes(scopes) { scope in
        if scope.organizationID != nil {
            throw KiloUsageError.serviceUnavailable(503)
        }
        return KiloScopeView(id: scope.scopeIdentifier, title: scope.displayName, view: nil, errorMessage: nil)
    }

    #expect(results.map(\.id) == ["personal", "org:fixture-org"])
    #expect(results[0].errorMessage == nil)
    #expect(results[1].errorMessage == "Could not refresh Fixture Organization.")
}
