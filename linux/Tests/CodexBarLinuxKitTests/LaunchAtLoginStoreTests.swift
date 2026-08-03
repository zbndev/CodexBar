import Foundation
import Testing

@testable import CodexBarLinuxKit

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func makeStore(_ directory: URL) -> LaunchAtLoginStore {
    LaunchAtLoginStore(directory: directory, executablePath: "/usr/bin/codexbar")
}

@Test func `enabling writes an autostart entry that launches the installed binary`() throws {
    let directory = tempDirectory()
    let store = makeStore(directory)

    try store.apply(true)

    let file = directory.appendingPathComponent("codexbar.desktop")
    let text = try String(contentsOf: file, encoding: .utf8)
    #expect(text.contains("Exec=/usr/bin/codexbar"))
    #expect(text.contains("Type=Application"))
    #expect(text.contains("X-GNOME-Autostart-enabled=true"))
    #expect(store.isEnabled)
}

@Test func `disabling removes the entry`() throws {
    let directory = tempDirectory()
    let store = makeStore(directory)
    try store.apply(true)

    try store.apply(false)

    #expect(!store.isEnabled)
    #expect(!FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("codexbar.desktop").path))
}

@Test func `disabling when nothing is there is not an error`() throws {
    let store = makeStore(tempDirectory())
    try store.apply(false)
    #expect(!store.isEnabled)
}

@Test func `enabling twice leaves one entry with the current path`() throws {
    let directory = tempDirectory()
    try makeStore(directory).apply(true)

    // A reinstall can move the binary; the second write must win.
    try LaunchAtLoginStore(directory: directory, executablePath: "/opt/codexbar/bin/codexbar")
        .apply(true)

    let text = try String(
        contentsOf: directory.appendingPathComponent("codexbar.desktop"), encoding: .utf8)
    #expect(text.contains("Exec=/opt/codexbar/bin/codexbar"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
}

@Test func `the default directory follows XDG_CONFIG_HOME`() {
    let directory = LaunchAtLoginStore.defaultDirectory(environment: ["XDG_CONFIG_HOME": "/tmp/cfg"])
    #expect(directory.path == "/tmp/cfg/autostart")
}

@Test func `an empty XDG_CONFIG_HOME falls back to the home directory`() {
    let directory = LaunchAtLoginStore.defaultDirectory(environment: ["XDG_CONFIG_HOME": ""])
    #expect(directory.path.hasSuffix("/.config/autostart"))
}
