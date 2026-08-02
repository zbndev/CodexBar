import Foundation

public protocol ExternalProcessHandle: Sendable {
    func wait() async -> Int32
    func terminate()
}

public enum SystemTerminal {
    public static func launch(
        executable: String,
        arguments: [String]) throws -> any ExternalProcessHandle
    {
        let environment = ProcessInfo.processInfo.environment
        guard let terminal = self.candidates(environment: environment)
            .compactMap({ self.resolvedExecutable(named: $0, environment: environment) })
            .first
        else {
            throw SystemTerminalError.unavailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: terminal)
        process.arguments = self.arguments(
            for: URL(fileURLWithPath: terminal).lastPathComponent,
            executable: executable,
            arguments: arguments)
        try process.run()
        return ProcessHandle(process: process)
    }

    static func candidates(environment: [String: String]) -> [String] {
        let fallback = ["xdg-terminal-exec", "foot", "kitty", "alacritty", "gnome-terminal", "konsole"]
        guard let terminal = environment["TERMINAL"],
              !terminal.isEmpty,
              terminal.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            return fallback
        }
        return [terminal] + fallback
    }

    static func arguments(for terminal: String, executable: String, arguments: [String]) -> [String] {
        switch terminal {
        case "foot", "kitty", "alacritty", "konsole":
            ["-e", executable] + arguments
        case "gnome-terminal":
            ["--", executable] + arguments
        case "xdg-terminal-exec":
            [executable] + arguments
        default:
            ["-e", executable] + arguments
        }
    }

    static func isExecutableAvailable(_ executable: String, environment: [String: String]) -> Bool {
        self.resolvedExecutable(named: executable, environment: environment) != nil
    }

    private static func resolvedExecutable(named executable: String, environment: [String: String]) -> String? {
        let fileManager = FileManager.default
        if executable.contains("/") {
            return fileManager.isExecutableFile(atPath: executable) ? executable : nil
        }
        let searchPath = environment["PATH"] ?? ""
        for directory in searchPath.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(executable).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

private final class ProcessHandle: ExternalProcessHandle, @unchecked Sendable {
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    func wait() async -> Int32 {
        self.process.waitUntilExit()
        return self.process.terminationStatus
    }

    func terminate() {
        if self.process.isRunning {
            self.process.terminate()
        }
    }
}

private enum SystemTerminalError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "No supported terminal application is available."
        }
    }
}
