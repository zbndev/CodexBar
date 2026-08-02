import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private func account(
    label: String,
    token: String,
    externalIdentifier: String?) -> ProviderTokenAccount
{
    ProviderTokenAccount(
        id: UUID(),
        label: label,
        token: token,
        addedAt: 1_000,
        lastUsed: nil,
        externalIdentifier: externalIdentifier)
}

private let now = Date(timeIntervalSince1970: 2_000)

@Test func `the external identifier is the stable github user id`() {
    let identity = CopilotUsageFetcher.GitHubUserIdentity(id: 42, login: "octocat")
    #expect(CopilotLogin.externalIdentifier(for: identity) == "github:user:42")
}

@Test func `a first login creates the account and makes it active`() {
    let data = CopilotLogin.merge(
        existing: nil,
        token: "gho_new",
        label: "octocat (individual)",
        externalIdentifier: "github:user:42",
        now: now)
    #expect(data.accounts.count == 1)
    #expect(data.accounts[0].token == "gho_new")
    #expect(data.accounts[0].label == "octocat (individual)")
    #expect(data.accounts[0].externalIdentifier == "github:user:42")
    #expect(data.activeIndex == 0)
    #expect(data.accounts[0].addedAt == 2_000)
}

@Test func `re-authenticating the same github user replaces its token in place`() {
    let existing = ProviderTokenAccountData(
        version: 1,
        accounts: [
            account(label: "someone-else", token: "gho_other", externalIdentifier: "github:user:7"),
            account(label: "octocat", token: "gho_old", externalIdentifier: "github:user:42"),
        ],
        activeIndex: 0)

    let data = CopilotLogin.merge(
        existing: existing,
        token: "gho_new",
        label: "octocat (business)",
        externalIdentifier: "github:user:42",
        now: now)

    #expect(data.accounts.count == 2)
    #expect(data.accounts[1].token == "gho_new")
    #expect(data.accounts[1].label == "octocat (business)")
    // The refreshed account keeps its identity and becomes the active one.
    #expect(data.accounts[1].id == existing.accounts[1].id)
    #expect(data.activeIndex == 1)
    // The untouched account is untouched.
    #expect(data.accounts[0].token == "gho_other")
}

@Test func `a legacy account identified by login is matched and upgraded`() {
    // Earlier revisions stored the bare login in externalIdentifier.
    let existing = ProviderTokenAccountData(
        version: 1,
        accounts: [account(label: "octocat", token: "gho_old", externalIdentifier: "octocat")],
        activeIndex: 0)

    let data = CopilotLogin.merge(
        existing: existing,
        token: "gho_new",
        label: "octocat",
        externalIdentifier: "github:user:42",
        legacyLogin: "octocat",
        now: now)

    #expect(data.accounts.count == 1)
    #expect(data.accounts[0].token == "gho_new")
    #expect(data.accounts[0].externalIdentifier == "github:user:42")
}

@Test func `a different github user is appended rather than overwriting`() {
    let existing = ProviderTokenAccountData(
        version: 1,
        accounts: [account(label: "octocat", token: "gho_old", externalIdentifier: "github:user:42")],
        activeIndex: 0)

    let data = CopilotLogin.merge(
        existing: existing,
        token: "gho_new",
        label: "hubot",
        externalIdentifier: "github:user:99",
        now: now)

    #expect(data.accounts.count == 2)
    #expect(data.accounts[0].token == "gho_old")
    #expect(data.accounts[1].token == "gho_new")
    #expect(data.activeIndex == 1)
}

@Test func `an unidentified login appends without claiming an existing account`() {
    // Identity lookup failed: no externalIdentifier, so nothing may be matched.
    let existing = ProviderTokenAccountData(
        version: 1,
        accounts: [account(label: "octocat", token: "gho_old", externalIdentifier: "github:user:42")],
        activeIndex: 0)

    let data = CopilotLogin.merge(
        existing: existing,
        token: "gho_new",
        label: "Account 2",
        externalIdentifier: nil,
        now: now)

    #expect(data.accounts.count == 2)
    #expect(data.accounts[0].externalIdentifier == "github:user:42")
    #expect(data.activeIndex == 1)
}

@Test func `merging preserves the stored version number`() {
    let existing = ProviderTokenAccountData(version: 3, accounts: [], activeIndex: 0)
    let data = CopilotLogin.merge(
        existing: existing, token: "t", label: "l", externalIdentifier: nil, now: now)
    #expect(data.version == 3)
}
