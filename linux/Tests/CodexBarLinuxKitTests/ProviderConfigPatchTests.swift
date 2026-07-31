import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `an empty patch changes nothing`() {
    let config = ProviderConfig(id: .claude, enabled: true, apiKey: "sk-test")
    let patched = ProviderConfigPatch().applying(to: config)
    #expect(patched.id == config.id)
    #expect(patched.enabled == config.enabled)
    #expect(patched.apiKey == config.apiKey)
}

@Test func `set fields overwrite and unset fields are preserved`() {
    let config = ProviderConfig(id: .ollama, enabled: true, source: .web, apiKey: "old")
    var patch = ProviderConfigPatch()
    patch.apiKey = "new"
    let patched = patch.applying(to: config)
    #expect(patched.apiKey == "new")
    #expect(patched.enabled == true)
    #expect(patched.source == .web)
}

@Test func `a field can be cleared explicitly`() {
    let config = ProviderConfig(id: .ollama, apiKey: "secret")
    var patch = ProviderConfigPatch()
    patch.apiKey = ""
    let patched = patch.applying(to: config)
    #expect(patched.apiKey == nil)
}

@Test func `a patch round-trips through JSON in the wire format`() throws {
    var patch = ProviderConfigPatch()
    patch.enabled = false
    patch.source = .oauth
    let data = try JSONEncoder().encode(patch)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"enabled\":false"))
    #expect(text.contains("\"source\":\"oauth\""))
    let decoded = try JSONDecoder().decode(ProviderConfigPatch.self, from: data)
    #expect(decoded == patch)
}

@Test func `the patch never changes the provider id`() {
    let config = ProviderConfig(id: .claude)
    var patch = ProviderConfigPatch()
    patch.apiKey = "x"
    #expect(patch.applying(to: config).id == .claude)
}
