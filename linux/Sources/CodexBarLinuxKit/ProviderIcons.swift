import Foundation

/// Reads provider brand icons from the resource root.
///
/// In a checkout that root is the upstream `Sources/CodexBar/Resources`, so a
/// sync picks up new or changed icons with no action here. An installed
/// package reads its own copy, made when the package was built.
public enum ProviderIcons {
    /// Directory holding `ProviderIcon-*.svg`: the installed resource root
    /// when there is one, the repository checkout otherwise.
    public static var resourcesDirectory: URL {
        LinuxResourceRoot.providerResources
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
