import Foundation

/// Authenticated seat material. Session tokens or an API key; never raw strings outside adapters.
/// Not Codable: secrets must not ride general encoders. Keychain uses an adapter-local payload.
public enum Credential: Sendable, Equatable, Hashable {
    case session(access: AccessToken, refresh: RefreshToken, expiresAt: Date)
    case apiKey(APIKey)
}

extension Credential: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .session: "<Credential.session>"
        case .apiKey: "<Credential.apiKey>"
        }
    }

    public var debugDescription: String { description }
}
