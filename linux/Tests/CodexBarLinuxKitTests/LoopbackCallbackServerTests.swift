import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import CodexBarLinuxKit

private func get(_ url: URL) async {
    // The listener answers and closes; a transport error here is not the
    // subject under test, so it is swallowed and the assertions run on what
    // the server observed.
    _ = try? await URLSession.shared.data(from: url)
}

@Test func `binding to port zero reports the assigned ephemeral port`() throws {
    let server = try LoopbackCallbackServer()
    defer { server.close() }
    #expect(server.port != 0)
}

@Test func `a callback request is parsed into its path and query items`() async throws {
    let server = try LoopbackCallbackServer(path: "/auth/callback")
    defer { server.close() }

    async let received = server.waitForRequest(timeout: 10)
    await get(URL(string: "http://127.0.0.1:\(server.port)/auth/callback?code=abc%20123&state=xyz")!)

    let request = try await received
    #expect(request.path == "/auth/callback")
    #expect(request.queryItems["code"] == "abc 123")
    #expect(request.queryItems["state"] == "xyz")
}

@Test func `a request to another path is answered but does not end the wait`() async throws {
    let server = try LoopbackCallbackServer(path: "/callback")
    defer { server.close() }

    async let received = server.waitForRequest(timeout: 10)
    // Browsers really do this: the callback page triggers a favicon fetch.
    await get(URL(string: "http://127.0.0.1:\(server.port)/favicon.ico")!)
    await get(URL(string: "http://127.0.0.1:\(server.port)/callback?code=late")!)

    let request = try await received
    #expect(request.queryItems["code"] == "late")
}

@Test func `an error redirect is delivered like any other callback`() async throws {
    let server = try LoopbackCallbackServer()
    defer { server.close() }

    async let received = server.waitForRequest(timeout: 10)
    await get(URL(string: "http://127.0.0.1:\(server.port)/callback?error=access_denied")!)

    let request = try await received
    #expect(request.queryItems["error"] == "access_denied")
    #expect(request.queryItems["code"] == nil)
}

@Test func `waiting past the deadline throws timedOut`() async throws {
    let server = try LoopbackCallbackServer()
    defer { server.close() }
    await #expect(throws: LoopbackCallbackServer.ServerError.timedOut) {
        _ = try await server.waitForRequest(timeout: 0.5)
    }
}

@Test func `closing while waiting throws closed rather than hanging`() async throws {
    let server = try LoopbackCallbackServer()
    // A Task rather than `async let`: Swift Testing cannot capture an
    // `async let` variable inside the #expect(throws:) closure.
    let waiter = Task { try await server.waitForRequest(timeout: 30) }
    try await Task.sleep(nanoseconds: 200_000_000)
    server.close()
    await #expect(throws: LoopbackCallbackServer.ServerError.closed) {
        _ = try await waiter.value
    }
}

@Test func `two servers can run at once on distinct ports`() throws {
    let first = try LoopbackCallbackServer()
    defer { first.close() }
    let second = try LoopbackCallbackServer()
    defer { second.close() }
    #expect(first.port != second.port)
}

@Test func `a waiting request observes cancellation`() async throws {
    let server = try LoopbackCallbackServer(port: 0, path: "/callback")
    defer { server.close() }
    let task = Task { try await server.waitForRequest(timeout: 300) }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("expected CancellationError")
    } catch is CancellationError {}
}
