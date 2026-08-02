import CodexBarCore
import Foundation

public struct KiloScopeView: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let view: ProviderView?
    public let errorMessage: String?

    public init(id: String, title: String, view: ProviderView?, errorMessage: String?) {
        self.id = id
        self.title = title
        self.view = view
        self.errorMessage = errorMessage
    }
}

public struct KiloOrganizationsPayload: Codable, Equatable, Sendable {
    public let organizations: [KiloOrganization]
    public let enabledIDs: [String]
    public let scopes: [KiloScopeView]
    public let isRefreshing: Bool
    public let errorMessage: String?

    public init(
        organizations: [KiloOrganization] = [],
        enabledIDs: [String] = [],
        scopes: [KiloScopeView] = [],
        isRefreshing: Bool = false,
        errorMessage: String? = nil)
    {
        self.organizations = organizations
        self.enabledIDs = enabledIDs
        self.scopes = scopes
        self.isRefreshing = isRefreshing
        self.errorMessage = errorMessage
    }
}

/// Shared display-only Kilo state used by settings and the usage store.
public final class KiloOrganizationsState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: KiloOrganizationsPayload

    public init(payload: KiloOrganizationsPayload = KiloOrganizationsPayload()) {
        self.value = payload
    }

    public func payload() -> KiloOrganizationsPayload {
        self.lock.withLock { self.value }
    }

    public func replace(
        organizations: [KiloOrganization],
        enabledIDs: [String],
        scopes: [KiloScopeView] = [],
        isRefreshing: Bool = false,
        errorMessage: String? = nil)
    {
        self.lock.withLock {
            self.value = KiloOrganizationsPayload(
                organizations: organizations,
                enabledIDs: enabledIDs,
                scopes: scopes,
                isRefreshing: isRefreshing,
                errorMessage: errorMessage)
        }
    }

    public func beginRefresh() {
        self.lock.withLock {
            self.value = KiloOrganizationsPayload(
                organizations: self.value.organizations,
                enabledIDs: self.value.enabledIDs,
                scopes: self.value.scopes,
                isRefreshing: true,
                errorMessage: nil)
        }
    }

    public func finishScopeRefresh(scopes: [KiloScopeView]) {
        self.lock.withLock {
            self.value = KiloOrganizationsPayload(
                organizations: self.value.organizations,
                enabledIDs: self.value.enabledIDs,
                scopes: scopes,
                isRefreshing: false,
                errorMessage: nil)
        }
    }

    public func failRefresh() {
        self.lock.withLock {
            self.value = KiloOrganizationsPayload(
                organizations: self.value.organizations,
                enabledIDs: self.value.enabledIDs,
                scopes: self.value.scopes,
                isRefreshing: false,
                errorMessage: "Could not load Kilo organizations.")
        }
    }
}

public struct KiloOrganizationRefresh: Sendable {
    public let organizations: [KiloOrganization]
    public let enabledIDs: [String]
}

public struct KiloOrganizationCoordinator: Sendable {
    private let fetch: @Sendable () async throws -> [KiloOrganization]

    public init(fetch: @escaping @Sendable () async throws -> [KiloOrganization]) {
        self.fetch = fetch
    }

    public func refresh(previousEnabledIDs: [String]) async throws -> KiloOrganizationRefresh {
        let fetchedOrganizations = try await self.fetch()
        var organizationsByID: [String: KiloOrganization] = [:]
        var orderedIDs: [String] = []

        for organization in fetchedOrganizations {
            if organizationsByID[organization.id] == nil {
                orderedIDs.append(organization.id)
            }
            organizationsByID[organization.id] = organization
        }

        let organizations = orderedIDs.compactMap { organizationsByID[$0] }
        let knownIDs = Set(orderedIDs)
        let enabledIDs = previousEnabledIDs.filter { knownIDs.contains($0) }
        return KiloOrganizationRefresh(organizations: organizations, enabledIDs: enabledIDs)
    }

    public static func refreshScopes(
        _ scopes: [KiloUsageScope],
        fetch: @escaping @Sendable (KiloUsageScope) async throws -> KiloScopeView) async -> [KiloScopeView]
    {
        let results = await withTaskGroup(of: KiloScopeView.self, returning: [KiloScopeView].self) { group in
            for scope in scopes {
                group.addTask {
                    do {
                        return try await fetch(scope)
                    } catch {
                        return KiloScopeView(
                            id: scope.scopeIdentifier,
                            title: scope.displayName,
                            view: nil,
                            errorMessage: "Could not refresh \(scope.displayName).")
                    }
                }
            }
            var collected: [KiloScopeView] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        let resultsByID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        return scopes.compactMap { resultsByID[$0.scopeIdentifier] }
    }
}
