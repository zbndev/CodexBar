import CodexBarCore
import Testing
@testable import CodexBarLinuxKit

@Suite
struct ExternalCredentialLoginTests {
    @Test
    func `Google login assistants use official executables without a shell`() throws {
        let gemini = try #require(ExternalCredentialLogin.catalog[.gemini])
        let antigravity = try #require(ExternalCredentialLogin.catalog[.antigravity])
        let vertex = try #require(ExternalCredentialLogin.catalog[.vertexai])
        #expect(gemini.executableCandidates == ["gemini"])
        #expect(antigravity.executableCandidates == ["antigravity"])
        #expect(vertex.arguments == ["auth", "application-default", "login"])
        #expect([gemini, antigravity, vertex].allSatisfy {
            !$0.arguments.contains(where: { $0.contains(";") || $0.contains("$(") })
        })
    }

    @Test
    func `missing official tools report their fixed executable names`() async throws {
        let environment = ["PATH": "", "HOME": "/tmp/codexbar-no-adc"]
        #expect(await ExternalCredentialLogin.geminiReadiness(
            environment: environment,
            coreStrategyAvailable: { _ in false }) == .unavailable(executable: "gemini"))
        #expect(await ExternalCredentialLogin.antigravityReadiness(
            environment: environment,
            coreStrategyAvailable: { _ in false }) == .unavailable(executable: "antigravity"))
        #expect(await ExternalCredentialLogin.vertexReadiness(environment: environment) == .unavailable(executable: "gcloud"))
    }

    @Test
    func `terminal adapters use fixed argument vectors`() {
        #expect(SystemTerminal.arguments(for: "foot", executable: "gemini", arguments: []) == ["-e", "gemini"])
        #expect(SystemTerminal.arguments(for: "kitty", executable: "gemini", arguments: []) == ["-e", "gemini"])
        #expect(SystemTerminal.arguments(for: "alacritty", executable: "gemini", arguments: []) == ["-e", "gemini"])
        #expect(SystemTerminal.arguments(for: "gnome-terminal", executable: "gemini", arguments: []) == ["--", "gemini"])
        #expect(SystemTerminal.arguments(for: "konsole", executable: "gemini", arguments: []) == ["-e", "gemini"])
        #expect(SystemTerminal.arguments(
            for: "xdg-terminal-exec",
            executable: "gcloud",
            arguments: ["auth", "application-default", "login"])
            == ["gcloud", "auth", "application-default", "login"])
    }

    @Test
    func `terminal selection rejects terminal values containing whitespace`() {
        #expect(SystemTerminal.candidates(environment: ["TERMINAL": "kitty --single-instance"])
            == ["xdg-terminal-exec", "foot", "kitty", "alacritty", "gnome-terminal", "konsole"])
    }
}
