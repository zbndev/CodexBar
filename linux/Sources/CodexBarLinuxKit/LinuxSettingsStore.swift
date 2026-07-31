import CodexBarCore
import Foundation

/// Persists `LinuxSettings` to its own JSON file, next to the shared
/// `config.json` but separate from it — the config file is shared with the
/// CLI and upstream, this one is Linux-only.
public final class LinuxSettingsStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Mirrors `CodexBarConfigStore`'s path resolution so both files always
    /// sit in the same directory:
    /// `CODEXBAR_CONFIG` (its directory) → `$XDG_CONFIG_HOME/codexbar` →
    /// existing `~/.config/codexbar` → existing `~/.codexbar` → the
    /// `~/.config/codexbar` default.
    public static func defaultURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default) -> URL
    {
        CodexBarConfigStore.defaultURL(
            home: home,
            environment: environment,
            fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent("linux-settings.json")
    }

    public func load() -> LinuxSettings {
        guard let data = try? Data(contentsOf: self.fileURL) else { return LinuxSettings() }
        return (try? JSONDecoder().decode(LinuxSettings.self, from: data)) ?? LinuxSettings()
    }

    public func save(_ settings: LinuxSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try data.write(to: self.fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: self.fileURL.path)
    }
}
