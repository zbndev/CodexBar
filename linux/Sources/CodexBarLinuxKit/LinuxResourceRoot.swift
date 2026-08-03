import Foundation

/// Where provider icons, localization catalogs and the app icon come from.
///
/// In a checkout they come from the repository, which lets a sync from
/// upstream pick up a redrawn icon or a new translation for free. An installed
/// package has no checkout, so packaging copies the same files under
/// `<prefix>/share/codexbar/resources` and this type finds them from the
/// executable's own path — no environment variable, no configuration.
///
/// The installed branch is preferred when present, so a package never reads a
/// checkout that happens to be lying around.
public enum LinuxResourceRoot {
    /// `<prefix>/share/codexbar` when the executable sits in
    /// `<prefix>/lib/codexbar/`, else nil.
    ///
    /// `/proc/self/exe` is already resolved by `Bundle.main.executableURL` on
    /// Linux, so the `/usr/bin/codexbar` symlink does not defeat this.
    public static func installed(
        executableURL: URL? = nil,
        fileManager: FileManager = .default) -> URL?
    {
        guard let executable = executableURL ?? Bundle.main.executableURL else { return nil }
        let prefix = executable
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()  // …/lib/codexbar
            .deletingLastPathComponent()  // …/lib
            .deletingLastPathComponent()  // …/<prefix>
        let candidate = prefix.appendingPathComponent("share/codexbar", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }
        return candidate
    }

    /// The repository root, for development builds.
    public static var checkout: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // …/linux/Sources/CodexBarLinuxKit
            .deletingLastPathComponent() // …/linux/Sources
            .deletingLastPathComponent() // …/linux
            .deletingLastPathComponent() // repository root
    }

    /// Directory holding `ProviderIcon-*.svg` and `<locale>.lproj/…`.
    public static var providerResources: URL {
        self.installed()?.appendingPathComponent("resources", isDirectory: true)
            ?? self.checkout.appendingPathComponent("Sources/CodexBar/Resources", isDirectory: true)
    }
}
