import Foundation

/// Controls whether email may appear in user-visible surfaces.
public enum IdentityDisplayPolicy: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case revealEmail
    case maskEmail

    public static let defaultsKey = "identityDisplayPolicy"
}
