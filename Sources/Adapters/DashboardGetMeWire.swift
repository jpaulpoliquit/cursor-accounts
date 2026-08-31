import CursorBarDomain
import Foundation

struct GetMeWireDTO: Decodable, Sendable {
    var email: String?
    var firstName: String?
    var lastName: String?
    var createdAt: String?
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
            emailRaw: dto.email,
            firstName: dto.firstName,
            lastName: dto.lastName
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
}
