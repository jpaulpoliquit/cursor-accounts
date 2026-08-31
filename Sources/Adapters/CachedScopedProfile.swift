import CursorBarDomain
import Foundation

/// Optional profile fields from `cursorAuth/cachedScopedProfile`. Parse failure is non-fatal.
public struct CachedScopedProfile: Sendable, Equatable {
    public let displayName: DisplayName?
    public let pictureURL: URL?

    public init(displayName: DisplayName?, pictureURL: URL?) {
        self.displayName = displayName
        self.pictureURL = pictureURL
    }

    /// Returns nil when JSON is missing, empty, or malformed. Never throws into bootstrap.
    public static func parse(jsonText: String?) -> CachedScopedProfile? {
        guard let jsonText else { return nil }
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let rawName = object["displayName"] as? String
        let displayName = rawName.flatMap(DisplayName.init)
        let pictureURL = ProfilePictureURL.parse(from: object)
        if displayName == nil, pictureURL == nil {
            return CachedScopedProfile(displayName: nil, pictureURL: nil)
        }
        return CachedScopedProfile(displayName: displayName, pictureURL: pictureURL)
    }
}
