import Foundation

/// The tray's own icon, taken from the app icon upstream already ships.
///
/// The tray previously asked for `utilities-system-monitor`, a stock
/// freedesktop name, so every host drew someone else's generic gauge.
///
/// Read from the repository at runtime rather than copied into this package,
/// for the reason `ProviderIcons` gives: a sync from upstream then picks up a
/// redrawn icon with no action here. libayatana wants a *themed name plus a
/// search path*, not a file, so the asset is materialised into a private cache
/// directory under the name the tray asks for. That also keeps the search path
/// pointed at a directory this app owns, instead of at `docs/`.
public enum AppIcon {
    /// The name the tray asks its host for, and the basename in `themePath`.
    public static let name = "codexbar"

    /// Repository root: `linux/` sits next to `docs/`.
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)      // …/linux/Sources/CodexBarLinuxKit/AppIcon.swift
            .deletingLastPathComponent()      // …/linux/Sources/CodexBarLinuxKit
            .deletingLastPathComponent()      // …/linux/Sources
            .deletingLastPathComponent()      // …/linux
            .deletingLastPathComponent()      // repository root
    }

    /// In preference order. `docs/icon.png` carries an alpha channel and so
    /// keeps its rounded corners on a light panel; the Icon Composer asset is
    /// opaque RGB and squares off, which is why it is only the fallback.
    private static let sourceCandidates = [
        "docs/icon.png",
        "Icon.icon/Assets/codexbar.png",
    ]

    /// Directory to hand libayatana as its icon theme path, or nil when no
    /// source asset could be found — callers then keep the stock icon name so
    /// the tray still appears rather than vanishing.
    public static func themePath(
        root: URL? = nil,
        cacheDirectory: URL? = nil,
        fileManager: FileManager = .default) -> String?
    {
        let root = root ?? self.repositoryRoot
        guard let source = self.sourceCandidates
            .map({ root.appendingPathComponent($0) })
            .first(where: { fileManager.fileExists(atPath: $0.path) })
        else { return nil }

        let directory = cacheDirectory ?? self.defaultCacheDirectory
        let destination = directory.appendingPathComponent("\(self.name).png")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // Copy only when the source moved on: the tray reloads the file by
            // path, and rewriting it every launch would be pointless churn.
            if self.isStale(destination: destination, source: source, fileManager: fileManager) {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
            }
        } catch {
            return nil
        }
        return directory.path
    }

    private static func isStale(destination: URL, source: URL, fileManager: FileManager) -> Bool {
        guard let destinationAttributes = try? fileManager.attributesOfItem(atPath: destination.path),
              let sourceAttributes = try? fileManager.attributesOfItem(atPath: source.path)
        else { return true }
        let sameSize = (destinationAttributes[.size] as? Int) == (sourceAttributes[.size] as? Int)
        let destinationDate = destinationAttributes[.modificationDate] as? Date
        let sourceDate = sourceAttributes[.modificationDate] as? Date
        guard let destinationDate, let sourceDate else { return true }
        return !sameSize || destinationDate < sourceDate
    }

    private static var defaultCacheDirectory: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
        return base.appendingPathComponent("codexbar/icons", isDirectory: true)
    }
}
