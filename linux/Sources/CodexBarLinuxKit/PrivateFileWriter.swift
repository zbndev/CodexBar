#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Foundation

/// Writes a credential file so it is never briefly world-readable and never
/// half-written.
///
/// The pattern is Core's (`CodexOAuthCredentials.swift:189-226`): create the
/// staging file with `O_EXCL` and mode 0600 so the permissions are right
/// before any byte lands, fsync, then `rename` over the target — atomic within
/// a filesystem. `Data.write(to:)` gives neither property and must not be used
/// for anything holding a token or a cookie.
public enum PrivateFileWriter {
    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let staged = directory.appendingPathComponent(
            ".\(url.lastPathComponent).codexbar-staged-\(UUID().uuidString)",
            isDirectory: false)
        let stagedPath = staged.path

        let descriptor = stagedPath.withCString {
            open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600))
        }
        guard descriptor >= 0 else { throw Self.posixError(errno, path: stagedPath) }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var isOpen = true
        do {
            guard fchmod(descriptor, mode_t(0o600)) == 0 else {
                throw Self.posixError(errno, path: stagedPath)
            }
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            isOpen = false

            let renamed = stagedPath.withCString { source in
                url.path.withCString { destination in rename(source, destination) }
            }
            guard renamed == 0 else { throw Self.posixError(errno, path: url.path) }
        } catch {
            if isOpen { try? handle.close() }
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }

    private static func posixError(_ code: Int32, path: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: path])
    }
}
