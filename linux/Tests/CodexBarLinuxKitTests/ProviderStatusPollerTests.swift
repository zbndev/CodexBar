import CodexBarCore
import Foundation
import Testing

@testable import CodexBarLinuxKit

private final class StatusPollerFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var statusCode = 200
    private var requests: [ProviderStatusRequest] = []
    private var transitions: [ProviderStatusTransition] = []
    private var enabled = true

    func response(for request: ProviderStatusRequest) async -> Int {
        self.lock.withLock {
            self.requests.append(request)
            return self.statusCode
        }
    }

    func setStatusCode(_ value: Int) { self.lock.withLock { self.statusCode = value } }
    func setEnabled(_ value: Bool) { self.lock.withLock { self.enabled = value } }
    func isEnabled() -> Bool { self.lock.withLock { self.enabled } }
    func append(_ transition: ProviderStatusTransition) { self.lock.withLock { self.transitions.append(transition) } }
    func requestSnapshot() -> [ProviderStatusRequest] { self.lock.withLock { self.requests } }
    func transitionSnapshot() -> [ProviderStatusTransition] { self.lock.withLock { self.transitions } }
}

@Test func `status polling emits only unavailable and recovered edges without cookies`() async throws {
    // Given
    let fixture = StatusPollerFixture()
    let descriptors = ProviderDescriptorRegistry.all.filter { $0.metadata.statusPageURL != nil }
    let poller = ProviderStatusPoller(
        descriptors: descriptors,
        statusChecksEnabled: fixture.isEnabled,
        transport: fixture.response,
        onTransition: fixture.append)

    // When
    await poller.pollOnce()
    await poller.pollOnce()
    fixture.setStatusCode(503)
    await poller.pollOnce()
    await poller.pollOnce()
    fixture.setStatusCode(200)
    await poller.pollOnce()

    // Then
    let expectedHosts = Set(descriptors.compactMap { URL(string: $0.metadata.statusPageURL ?? "")?.host })
    let requests = fixture.requestSnapshot()
    #expect(Set(requests.compactMap(\.url.host)) == expectedHosts)
    #expect(requests.allSatisfy { $0.timeout == .seconds(10) && $0.headers["Cookie"] == nil })
    #expect(poller.cadence == .seconds(10 * 60))
    let unavailable = descriptors.map { ProviderStatusTransition.unavailable(providerID: $0.id.rawValue) }
    let recovered = descriptors.map { ProviderStatusTransition.recovered(providerID: $0.id.rawValue) }
    #expect(fixture.transitionSnapshot() == unavailable + recovered)
}

@Test func `disabled status checks cancel polling and suppress transitions`() async {
    // Given
    let fixture = StatusPollerFixture()
    let descriptor = try! #require(ProviderDescriptorRegistry.all.first { $0.metadata.statusPageURL != nil })
    let poller = ProviderStatusPoller(
        descriptors: [descriptor],
        statusChecksEnabled: fixture.isEnabled,
        transport: fixture.response,
        onTransition: fixture.append)
    poller.start()

    // When
    fixture.setEnabled(false)
    await poller.pollOnce()

    // Then
    #expect(!poller.isRunning)
    #expect(fixture.transitionSnapshot().isEmpty)
}
