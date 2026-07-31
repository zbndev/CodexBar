import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `a nil config falls back to providers enabled by default`() {
    let providers = ProviderCatalog.enabledProviders(config: nil)
    #expect(!providers.isEmpty)
    #expect(providers.allSatisfy { $0.metadata.defaultEnabled })
}

@Test func `an explicit config selects exactly the providers it enables`() {
    let config = CodexBarConfig(
        version: 1,
        providers: [
            ProviderConfig(id: .claude, enabled: true),
            ProviderConfig(id: .cursor, enabled: false),
        ])
    let ids = ProviderCatalog.enabledProviders(config: config).map(\.id)
    #expect(ids.contains(.claude))
    #expect(!ids.contains(.cursor))
}

@Test func `every registered provider can produce a placeholder view`() {
    for descriptor in ProviderDescriptorRegistry.all {
        let view = ProviderCatalog.placeholderView(for: descriptor, enabled: true)
        #expect(view.id == descriptor.id.rawValue)
        #expect(!view.displayName.isEmpty)
        #expect(!view.iconResourceName.isEmpty)
        #expect(view.isLoading)
    }
}

@Test func `a provider colour renders as a six digit hex string`() {
    let color = ProviderColor(red: 1.0, green: 0.0, blue: 0.5)
    #expect(color.hexString == "#FF0080")
}

@Test func `a snapshot payload round-trips through JSON`() throws {
    let payload = ProviderSnapshotPayload(
        generatedAt: Date(timeIntervalSince1970: 0),
        providers: [
            ProviderCatalog.placeholderView(
                for: ProviderDescriptorRegistry.descriptor(for: .claude),
                enabled: true),
        ])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(
        ProviderSnapshotPayload.self,
        from: try encoder.encode(payload))
    #expect(decoded == payload)
}
