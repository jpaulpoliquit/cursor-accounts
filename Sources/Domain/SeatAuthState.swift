import Foundation

public enum SeatAuthState: String, Codable, Sendable, Equatable, Hashable {
    case signedOut
    case signingIn
    case signedIn
    case needsReauth
}
