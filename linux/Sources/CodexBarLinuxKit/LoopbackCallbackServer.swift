#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Foundation

/// A one-shot HTTP listener on `127.0.0.1`, used as an OAuth `redirect_uri`.
///
/// Deliberately minimal: one expected path, no keep-alive, no TLS, one
/// interesting request. `CLILocalHTTPServer` in `Sources/CodexBarCLI/` looks
/// like the thing to reuse, but it is internal to an executable target and
/// cannot be imported from here.
///
/// Binds loopback only, so nothing outside this machine can reach it.
public final class LoopbackCallbackServer: @unchecked Sendable {
    public struct Request: Equatable, Sendable {
        public let path: String
        public let queryItems: [String: String]

        public init(path: String, queryItems: [String: String]) {
            self.path = path
            self.queryItems = queryItems
        }
    }

    public enum ServerError: Error, Equatable {
        case socketFailed(Int32)
        case bindFailed(Int32)
        case listenFailed(Int32)
        case timedOut
        /// `close()` was called, or the socket died, while waiting.
        case closed
    }

    /// The port actually bound. When the caller asks for 0 the kernel assigns
    /// one and this reports it — which is what goes into `redirect_uri`.
    public private(set) var port: UInt16 = 0

    private let expectedPath: String
    private let successHTML: String
    private let lock = NSLock()
    private var descriptor: Int32 = -1

    private static let defaultSuccessHTML = """
    <!doctype html><meta charset="utf-8"><title>CodexBar</title>
    <body style="font:16px system-ui;display:flex;height:90vh;align-items:center;justify-content:center">
    <p>Signed in. You can close this tab and return to CodexBar.</p>
    """

    public init(
        port: UInt16 = 0,
        path: String = "/callback",
        successHTML: String? = nil) throws
    {
        self.expectedPath = path
        self.successHTML = successHTML ?? Self.defaultSuccessHTML

        let handle = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        guard handle >= 0 else { throw ServerError.socketFailed(errno) }

        var reuse: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian // 127.0.0.1

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(handle, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            Glibc.close(handle)
            throw ServerError.bindFailed(code)
        }

        guard listen(handle, 4) == 0 else {
            let code = errno
            Glibc.close(handle)
            throw ServerError.listenFailed(code)
        }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(handle, socketAddress, &length)
            }
        }
        self.port = named == 0 ? UInt16(bigEndian: actual.sin_port) : port
        self.descriptor = handle
    }

    deinit {
        self.close()
    }

    /// Idempotent. Wakes a pending `waitForRequest`, which then throws `.closed`.
    public func close() {
        self.lock.lock()
        let handle = self.descriptor
        self.descriptor = -1
        self.lock.unlock()
        if handle >= 0 { _ = Glibc.close(handle) }
    }

    private var currentDescriptor: Int32 {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.descriptor
    }

    /// Waits for a request to the expected path and returns its query items.
    ///
    /// Requests to any other path are answered `404` and ignored — a browser
    /// commonly asks for `/favicon.ico` right after loading the success page,
    /// and treating that as the callback would abort the login.
    public func waitForRequest(timeout: TimeInterval) async throws -> Request {
        let deadline = Date().addingTimeInterval(timeout)
        return try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread { [self] in
                do {
                    continuation.resume(returning: try self.accept(until: deadline))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func accept(until deadline: Date) throws -> Request {
        while true {
            let handle = self.currentDescriptor
            guard handle >= 0 else { throw ServerError.closed }

            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw ServerError.timedOut }

            var descriptor = pollfd(fd: handle, events: Int16(POLLIN), revents: 0)
            // Cap each wait so close() is noticed promptly even on a long deadline.
            let slice = Int32(min(remaining, 0.25) * 1000)
            let ready = poll(&descriptor, 1, max(slice, 1))
            if ready < 0 {
                if errno == EINTR { continue }
                throw ServerError.closed
            }
            if ready == 0 { continue }

            let client = Glibc.accept(handle, nil, nil)
            guard client >= 0 else {
                if errno == EINTR || errno == ECONNABORTED { continue }
                throw ServerError.closed
            }
            defer { _ = Glibc.close(client) }

            guard let line = Self.readRequestLine(client) else { continue }
            guard let (path, queryItems) = Self.parseTarget(line) else {
                Self.respond(client, status: "400 Bad Request", body: "Bad request")
                continue
            }
            guard path == self.expectedPath else {
                Self.respond(client, status: "404 Not Found", body: "Not found")
                continue
            }
            Self.respond(client, status: "200 OK", body: self.successHTML)
            return Request(path: path, queryItems: queryItems)
        }
    }

    /// Reads until the end of the header block, then returns the request line.
    /// Bounded so a hostile local process cannot make this allocate forever.
    private static func readRequestLine(_ client: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var accumulated = Data()
        while accumulated.count < 16_384 {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 { break }
            accumulated.append(contentsOf: buffer[0..<count])
            if accumulated.range(of: Data("\r\n\r\n".utf8)) != nil { break }
        }
        guard let text = String(data: accumulated, encoding: .utf8),
              let firstLine = text.components(separatedBy: "\r\n").first
        else {
            return nil
        }
        return firstLine
    }

    /// `GET /callback?code=… HTTP/1.1` → ("/callback", ["code": …]).
    /// Percent-decoding is `URLComponents`' job, so `code=abc%20123` arrives
    /// as `abc 123`.
    static func parseTarget(_ requestLine: String) -> (String, [String: String])? {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0].uppercased() == "GET" else { return nil }
        let target = String(parts[1])
        guard target.hasPrefix("/"),
              let components = URLComponents(string: "http://127.0.0.1\(target)")
        else {
            return nil
        }
        var queryItems: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value { queryItems[item.name] = value }
        }
        return (components.path, queryItems)
    }

    private static func respond(_ client: Int32, status: String, body: String) {
        let bodyData = Data(body.utf8)
        let head = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        var payload = Data(head.utf8)
        payload.append(bodyData)
        payload.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(client, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
    }
}
