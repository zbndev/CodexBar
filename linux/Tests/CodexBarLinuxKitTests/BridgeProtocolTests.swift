import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `a refresh command round-trips through JSON`() throws {
    let original = BridgeCommand.refresh(provider: "codex")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(BridgeCommand.self, from: data)
    #expect(decoded == original)
}

@Test func `a refresh command with no provider round-trips`() throws {
    let original = BridgeCommand.refresh(provider: nil)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(BridgeCommand.self, from: data)
    #expect(decoded == original)
}

@Test func `commands decode from the wire format the web UI sends`() throws {
    let json = #"{"type":"selectProvider","id":"claude"}"#
    let decoded = try JSONDecoder().decode(BridgeCommand.self, from: Data(json.utf8))
    #expect(decoded == .selectProvider(id: "claude"))
}

@Test func `an unknown command type decodes as a decoding error rather than crashing`() {
    let json = #"{"type":"somethingNobodyImplemented"}"#
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(BridgeCommand.self, from: Data(json.utf8))
    }
}

@Test func `an error event encodes with its message`() throws {
    let data = try JSONEncoder().encode(BridgeEvent.error(message: "boom"))
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"error\""))
    #expect(text.contains("boom"))
}

@Test func `event JSON embedded in a script literal escapes quotes and backslashes`() {
    let escaped = BridgeScriptEncoding.javaScriptStringLiteral(#"{"a":"b\c"}"#)
    #expect(escaped == #""{\"a\":\"b\\c\"}""#)
}
