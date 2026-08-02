import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `managed Codex account rows round-trip through JSON`() throws {
    let row = PaneRow.managedCodexAccounts(providerID: "codex")
    let decoded = try JSONDecoder().decode(PaneRow.self, from: JSONEncoder().encode(row))
    #expect(decoded == row)
}

@Test func `only the Codex pane renders managed account controls`() {
    let codex = ProviderPaneGenerator.rows(
        for: ProviderDescriptorRegistry.descriptor(for: .codex), config: nil)
    let claude = ProviderPaneGenerator.rows(
        for: ProviderDescriptorRegistry.descriptor(for: .claude), config: nil)
    #expect(codex.contains(.managedCodexAccounts(providerID: "codex")))
    #expect(!claude.contains { row in
        if case .managedCodexAccounts = row { return true }
        return false
    })
}
