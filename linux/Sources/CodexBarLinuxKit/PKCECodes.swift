import Crypto
import Foundation

/// One login attempt's PKCE material (RFC 7636) plus its CSRF `state`.
///
/// The verifier never leaves the process except in the token request; only the
/// challenge appears in the authorize URL the browser sees.
public struct PKCECodes: Equatable, Sendable {
    public let verifier: String
    public let challenge: String
    public let state: String

    public init(verifier: String, challenge: String, state: String) {
        self.verifier = verifier
        self.challenge = challenge
        self.state = state
    }

    /// Fresh codes for a new login attempt.
    ///
    /// 32 random bytes base64url-encode to 43 characters, the minimum the RFC
    /// allows and the length every reference implementation uses.
    public static func generate() -> PKCECodes {
        self.derive(
            verifier: self.randomBase64URL(byteCount: 32),
            state: self.randomBase64URL(byteCount: 16))
    }

    /// Computes the challenge for a given verifier. Split out from `generate`
    /// so the RFC's published test vector can be asserted directly.
    public static func derive(verifier: String, state: String) -> PKCECodes {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return PKCECodes(
            verifier: verifier,
            challenge: self.base64URL(Data(digest)),
            state: state)
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        var bytes = Data(count: byteCount)
        for index in 0..<byteCount {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        }
        return self.base64URL(bytes)
    }

    /// base64url without padding, per RFC 7636 §A.
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
