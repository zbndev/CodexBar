import CodexBarCore
import Foundation

/// GitHub Copilot's device-code login.
///
/// The protocol lives in Core and needs nothing platform-specific
/// (`CopilotDeviceFlow.swift`); what is added here is the phase reporting the
/// UI needs — the user code has to be *shown*, not opened — and the mapping
/// onto a token account.
public enum CopilotLogin {
    /// The stable identity used to recognise a re-auth of the same GitHub user.
    public static func externalIdentifier(for identity: CopilotUsageFetcher.GitHubUserIdentity) -> String {
        "github:user:\(identity.id)"
    }

    /// Folds a freshly issued token into the stored account list.
    ///
    /// Matching is by stable GitHub user id, then by a bare login left behind
    /// by earlier revisions. When the identity could not be resolved at all,
    /// nothing is matched and the account is appended — claiming an existing
    /// account on a guess would silently overwrite someone else's token.
    public static func merge(
        existing: ProviderTokenAccountData?,
        token: String,
        label: String,
        externalIdentifier: String?,
        legacyLogin: String? = nil,
        now: Date) -> ProviderTokenAccountData
    {
        var accounts = existing?.accounts ?? []
        let version = existing?.version ?? 1

        let matchIndex: Int? = {
            guard let externalIdentifier else { return nil }
            if let index = accounts.firstIndex(where: { $0.externalIdentifier == externalIdentifier }) {
                return index
            }
            guard let legacyLogin else { return nil }
            return accounts.firstIndex {
                $0.externalIdentifier?.lowercased() == legacyLogin.lowercased()
            }
        }()

        if let matchIndex {
            let previous = accounts[matchIndex]
            accounts[matchIndex] = ProviderTokenAccount(
                id: previous.id,
                label: label,
                token: token,
                addedAt: previous.addedAt,
                lastUsed: previous.lastUsed,
                externalIdentifier: externalIdentifier,
                usageScope: previous.usageScope,
                organizationID: previous.organizationID,
                workspaceID: previous.workspaceID)
            return ProviderTokenAccountData(
                version: version,
                accounts: accounts,
                activeIndex: matchIndex)
        }

        accounts.append(ProviderTokenAccount(
            id: UUID(),
            label: label,
            token: token,
            addedAt: now.timeIntervalSince1970,
            lastUsed: nil,
            externalIdentifier: externalIdentifier))
        return ProviderTokenAccountData(
            version: version,
            accounts: accounts,
            activeIndex: accounts.count - 1)
    }

    /// Runs the whole flow and returns the account list to persist.
    ///
    /// - Parameter progress: receives `.showingDeviceCode` with the code the
    ///   user must type into GitHub. That code is a public display value —
    ///   it authorizes nothing on its own — so unlike every other secret here
    ///   it may cross into the UI.
    public static func run(
        enterpriseHost: String?,
        existing: ProviderTokenAccountData?,
        openURL: @escaping @Sendable (String) -> Void,
        progress: @escaping @Sendable (LoginPhase) -> Void,
        now: Date = Date()) async throws -> ProviderTokenAccountData
    {
        progress(.preparing)
        let host = (enterpriseHost?.isEmpty ?? true) ? nil : enterpriseHost
        let flow = CopilotDeviceFlow(enterpriseHost: host)

        let device = try await flow.requestDeviceCode()
        progress(.showingDeviceCode(
            code: device.userCode,
            url: device.verificationURLToOpen))
        openURL(device.verificationURLToOpen)

        let token = try await flow.pollForToken(
            deviceCode: device.deviceCode,
            interval: device.interval)

        progress(.saving)

        // Resolve who this token belongs to. If that fails while accounts
        // already exist, stop: appending an anonymous duplicate would leave a
        // stale token on the real account with no way to tell them apart.
        var label = "Account \((existing?.accounts.count ?? 0) + 1)"
        var identifier: String?
        var legacyLogin: String?
        do {
            let identity = try await CopilotUsageFetcher.fetchGitHubIdentity(token: token)
            identifier = self.externalIdentifier(for: identity)
            legacyLogin = identity.login
            label = identity.login
        } catch {
            guard existing?.accounts.isEmpty ?? true else {
                throw LoginError.malformedTokenResponse(
                    "GitHub login succeeded, but the account could not be identified. Try again.")
            }
        }

        let merged = self.merge(
            existing: existing,
            token: token,
            label: label,
            externalIdentifier: identifier,
            legacyLogin: legacyLogin,
            now: now)
        progress(.finished)
        return merged
    }
}
