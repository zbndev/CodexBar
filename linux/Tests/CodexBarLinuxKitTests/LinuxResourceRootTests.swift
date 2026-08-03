import Foundation
import Testing

@testable import CodexBarLinuxKit

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

@Test func `an installed layout is found from the executable's own path`() throws {
    let prefix = tempDirectory()
    let executable = prefix.appendingPathComponent("lib/codexbar/CodexBarLinux")
    let resources = prefix.appendingPathComponent("share/codexbar/resources")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("binary".utf8).write(to: executable)

    let found = LinuxResourceRoot.installed(executableURL: executable)

    // Compare resolved paths on both sides: the resolver resolves symlinks,
    // and the temporary directory may itself sit behind one.
    let expected = prefix.appendingPathComponent("share/codexbar").resolvingSymlinksInPath().path
    #expect(found?.resolvingSymlinksInPath().path == expected)
}

@Test func `a build tree is not mistaken for an installed layout`() throws {
    let root = tempDirectory()
    let executable = root.appendingPathComponent(".build/release/CodexBarLinux")
    try FileManager.default.createDirectory(
        at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("binary".utf8).write(to: executable)

    #expect(LinuxResourceRoot.installed(executableURL: executable) == nil)
}

@Test func `the checkout root holds the upstream resource directory`() {
    let resources = LinuxResourceRoot.checkout.appendingPathComponent("Sources/CodexBar/Resources")
    #expect(FileManager.default.fileExists(atPath: resources.path))
}
