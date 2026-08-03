import Foundation

/// Starts CodexBar with the desktop session, through the XDG autostart
/// directory.
///
/// The file is written rather than tracked: `LinuxSettings.launchAtLogin` is
/// the preference, and this store makes the filesystem match it. That means a
/// reinstall that moves the binary is repaired on the next launch, because the
/// entry is rewritten with the current executable path.
public struct LaunchAtLoginStore: Sendable {
    private let directory: URL
    private let executablePath: String

    private static let fileName = "codexbar.desktop"

    public init(directory: URL, executablePath: String) {
        self.directory = directory
        self.executablePath = executablePath
    }

    /// The running executable's own path, so a checkout build autostarts the
    /// checkout build and an installed one autostarts the installed one.
    public static func `default`(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> LaunchAtLoginStore
    {
        LaunchAtLoginStore(
            directory: self.defaultDirectory(environment: environment),
            executablePath: Bundle.main.executableURL?.resolvingSymlinksInPath().path
                ?? "/usr/bin/codexbar")
    }

    public static func defaultDirectory(environment: [String: String]) -> URL {
        let base = environment["XDG_CONFIG_HOME"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base.appendingPathComponent("autostart", isDirectory: true)
    }

    private var fileURL: URL {
        self.directory.appendingPathComponent(Self.fileName)
    }

    public var isEnabled: Bool {
        FileManager.default.fileExists(atPath: self.fileURL.path)
    }

    /// Writes or removes the entry. Writing is idempotent and always rewrites,
    /// so a stale `Exec` from an earlier install cannot survive.
    public func apply(_ enabled: Bool) throws {
        let manager = FileManager.default
        guard enabled else {
            if manager.fileExists(atPath: self.fileURL.path) {
                try manager.removeItem(at: self.fileURL)
            }
            return
        }

        try manager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let entry = """
        [Desktop Entry]
        Type=Application
        Name=CodexBar
        Comment=AI coding usage in your tray
        Exec=\(self.executablePath)
        Icon=codexbar
        Terminal=false
        X-GNOME-Autostart-enabled=true

        """
        try Data(entry.utf8).write(to: self.fileURL, options: .atomic)
        // Not 0600: the desktop session's autostart reader is a different
        // process and this file holds nothing private.
        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: self.fileURL.path)
    }
}
