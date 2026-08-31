import Foundation

/// Presentation-usable account identity after session-JWT hydration.
/// Subject-only JWT bindings are never enough for a connected seat.
public struct HydratedAccountIdentity: Sendable, Equatable, Hashable {
    public let email: Email?
    public let displayName: DisplayName?
    public let pictureURL: URL?
    public let isTeamAccount: Bool

    public var isUsableForPresentation: Bool {
        email != nil || displayName != nil
    }

    public init?(
        email: Email?,
        displayName: DisplayName?,
        pictureURL: URL? = nil,
        isTeamAccount: Bool = false
    ) {
        guard email != nil || displayName != nil else { return nil }
        self.email = email
        self.displayName = displayName
        self.pictureURL = pictureURL
        self.isTeamAccount = isTeamAccount
    }

    /// Parse GetMe-shaped fields into a usable identity. Rejects empty / email-shaped names.
    public static func fromProfile(
        emailRaw: String?,
        firstName: String?,
        lastName: String?,
        pictureRaw: String? = nil,
        isTeamAccount: Bool = false
    ) -> HydratedAccountIdentity? {
        let email = emailRaw.flatMap(Email.init)
        let displayName = composeDisplayName(firstName: firstName, lastName: lastName)
        return HydratedAccountIdentity(
            email: email,
            displayName: displayName,
            pictureURL: ProfilePictureURL.parse(pictureRaw),
            isTeamAccount: isTeamAccount
        )
    }

    public static func composeDisplayName(firstName: String?, lastName: String?) -> DisplayName? {
        let parts = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return DisplayName(parts.joined(separator: " "))
    }
}
