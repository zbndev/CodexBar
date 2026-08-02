import Foundation

/// Where a login has got to. Reported to the UI; Task 8 encodes it into a
/// `BridgeEvent`.
///
/// No case carries a credential — only phases, user-visible URLs, and the
/// device code, which is a public display value by design.
public enum LoginPhase: Equatable, Sendable {
    case preparing
    /// The browser has been opened at `url`; waiting on the loopback callback.
    case waitingForBrowser(url: String)
    /// The provider hosts the callback: the user copies a code from `url`
    /// and pastes it back.
    case awaitingCode(url: String)
    /// GitHub device flow: show `code`, send the user to `url`.
    case showingDeviceCode(code: String, url: String)
    case exchanging
    case saving
    case finished
    case failed(message: String)
}

public enum LoginError: Error, Equatable {
    case stateMismatch
    /// The authorization server refused, e.g. the user declined consent.
    case providerRejected(String)
    case noAuthorizationCode
    case tokenRequestFailed(status: Int, body: String)
    case malformedTokenResponse(String)
    case cancelled

    public var message: String {
        switch self {
        case .stateMismatch:
            "The login response did not match this request. Try again."
        case let .providerRejected(detail):
            "The provider rejected the login: \(detail)"
        case .noAuthorizationCode:
            "The provider redirected back without an authorization code."
        case let .tokenRequestFailed(status, body):
            "Token exchange failed (HTTP \(status)): \(body.prefix(200))"
        case let .malformedTokenResponse(detail):
            "The provider returned an unreadable token response: \(detail)"
        case .cancelled:
            "Login cancelled."
        }
    }
}
