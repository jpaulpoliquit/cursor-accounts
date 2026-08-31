import CursorBarDomain
import Foundation

struct GetMeWireDTO: Decodable, Sendable {
    var email: String?
    var firstName: String?
    var lastName: String?
    var createdAt: String?
    var picture: String?
    var pictureUrl: String?
    var pictureURL: String?
    var profilePictureUrl: String?
    var profile_picture_url: String?
    var avatarUrl: String?
    var photoUrl: String?
    var membershipType: String?
    var isEnterpriseUser: Bool?
    var isTeamAdmin: Bool?
    var teamName: String?
    var team_name: String?
    var teamId: Int?
    var team_id: Int?
    var user: NestedUser?

    struct NestedUser: Decodable, Sendable {
        var email: String?
        var firstName: String?
        var lastName: String?
        var picture: String?
        var pictureUrl: String?
        var profilePictureUrl: String?
    }
}

public struct GetMeProfile: Sendable, Equatable {
    public let identity: HydratedAccountIdentity
    public let createdAt: Date?

    public init(identity: HydratedAccountIdentity, createdAt: Date?) {
        self.identity = identity
        self.createdAt = createdAt
    }
}

enum DashboardGetMeWire {
    static func identity(from dto: GetMeWireDTO) throws -> HydratedAccountIdentity {
        try profile(from: dto).identity
    }

    static func profile(from dto: GetMeWireDTO) throws -> GetMeProfile {
        guard let identity = HydratedAccountIdentity.fromProfile(
            emailRaw: dto.email ?? dto.user?.email,
            firstName: dto.firstName ?? dto.user?.firstName,
            lastName: dto.lastName ?? dto.user?.lastName,
            pictureRaw: pictureRaw(from: dto),
            isTeamAccount: isTeamAccount(from: dto)
        ) else {
            throw DashboardWireCodec.DecodeError.missingAccountIdentity
        }
        return GetMeProfile(identity: identity, createdAt: parseCreatedAt(dto.createdAt))
    }

    /// Account onboarding timestamp when present. Not earliest usage; only an upper bound on history age.
    static func parseCreatedAt(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFractional.date(from: raw) { return date }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        if let millis = Int64(raw) {
            let seconds = abs(millis) > 10_000_000_000 ? TimeInterval(millis) / 1000.0 : TimeInterval(millis)
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private static func pictureRaw(from dto: GetMeWireDTO) -> String? {
        dto.profilePictureUrl
            ?? dto.profile_picture_url
            ?? dto.pictureUrl
            ?? dto.pictureURL
            ?? dto.picture
            ?? dto.avatarUrl
            ?? dto.photoUrl
            ?? dto.user?.profilePictureUrl
            ?? dto.user?.pictureUrl
            ?? dto.user?.picture
    }

    private static func isTeamAccount(from dto: GetMeWireDTO) -> Bool {
        if dto.isEnterpriseUser == true { return true }
        if dto.isTeamAdmin == true { return true }
        if (dto.teamId ?? dto.team_id ?? 0) > 0 { return true }
        let teamName = dto.teamName ?? dto.team_name ?? ""
        if !teamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let membership = (dto.membershipType ?? "").lowercased()
        return membership.contains("team")
            || membership.contains("enterprise")
            || membership.contains("business")
    }
}
