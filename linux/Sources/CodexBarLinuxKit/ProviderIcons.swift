import Foundation

/// Reads provider brand icons from the root package's resources.
///
/// The files are read at runtime rather than copied into this package, so a
/// sync from upstream picks up new or changed icons with no action here.
public enum ProviderIcons {
    /// Directory holding `ProviderIcon-*.svg`, resolved relative to this
    /// package: `linux/` sits next to `Sources/`.
    public static var resourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)          // …/linux/Sources/CodexBarLinuxKit/ProviderIcons.swift
            .deletingLastPathComponent()          // …/linux/Sources/CodexBarLinuxKit
            .deletingLastPathComponent()          // …/linux/Sources
            .deletingLastPathComponent()          // …/linux
            .deletingLastPathComponent()          // repository root
            .appendingPathComponent("Sources/CodexBar/Resources", isDirectory: true)
    }

    private static let cache = IconCache()

    private final class IconCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: String?] = [:]

        func value(for name: String, load: (String) -> String?) -> String? {
            self.lock.lock()
            defer { self.lock.unlock() }
            if let cached = self.storage[name] { return cached }
            let loaded = load(name)
            self.storage[name] = loaded
            return loaded
        }
    }

    /// The raw SVG markup for `resourceName`, or nil when the file is absent.
    public static func svg(named resourceName: String) -> String? {
        self.cache.value(for: resourceName) { name in
            let url = self.resourcesDirectory.appendingPathComponent("\(name).svg")
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }
}
