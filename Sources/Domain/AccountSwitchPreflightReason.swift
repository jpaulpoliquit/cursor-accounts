import Foundation

/// Why account-switch preflight failed. Cursor must remain running and untouched.
public enum AccountSwitchPreflightReason: Error, Codable, Sendable, Equatable, Hashable {
    case missingCredentials
    case identityNotHydrated
    case refreshFailed
    case apiKeyExchangeFailed
    case malformedSessionTokens
    case planRejected

    public var menuMessage: String {
        switch self {
        case .missingCredentials:
            return "This account has no saved session"
        case .identityNotHydrated:
            return "This account needs a usable email or name before switching"
        case .refreshFailed:
            return "Could not refresh the session for this account"
        case .apiKeyExchangeFailed:
            return "Could not exchange the API key for a session"
        case .malformedSessionTokens:
            return "Saved session tokens are not usable for Cursor"
        case .planRejected:
            return "Could not build a safe Cursor session update"
        }
    }
}
