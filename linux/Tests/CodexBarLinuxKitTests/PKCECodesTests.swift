import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `a derived challenge matches the RFC 7636 appendix B vector`() {
    // RFC 7636 §B: verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    // hashes to challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM".
    let codes = PKCECodes.derive(
        verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        state: "ignored")
    #expect(codes.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
}

@Test func `generated codes are base64url with no padding and legal lengths`() {
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    for _ in 0..<50 {
        let codes = PKCECodes.generate()
        // RFC 7636 §4.1 bounds the verifier at 43–128 characters.
        #expect(codes.verifier.count >= 43)
        #expect(codes.verifier.count <= 128)
        #expect(codes.verifier.allSatisfy { allowed.contains($0) })
        #expect(codes.challenge.allSatisfy { allowed.contains($0) })
        #expect(codes.state.allSatisfy { allowed.contains($0) })
        #expect(!codes.verifier.contains("="))
        #expect(!codes.challenge.contains("="))
    }
}

@Test func `generate produces a fresh verifier and state every time`() {
    let batch = (0..<64).map { _ in PKCECodes.generate() }
    #expect(Set(batch.map(\.verifier)).count == batch.count)
    #expect(Set(batch.map(\.state)).count == batch.count)
}

@Test func `the challenge is a pure function of the verifier`() {
    let first = PKCECodes.derive(verifier: "same-verifier-value", state: "a")
    let second = PKCECodes.derive(verifier: "same-verifier-value", state: "b")
    #expect(first.challenge == second.challenge)
    #expect(first.state != second.state)
}
