import Foundation

/// Active Cursor IDE identity derived from shared-profile auth rows.
public struct CursorIDEIdentity: Sendable, Equatable, Hashable {
    public let subject: String
    public let email: Email?

    public init(subject: String, email: Email?) {
        self.subject = subject
        self.email = email
    }

    /// Builds identity from access JWT + cached email text. Nil when subject is unusable.
    public static func from(accessTokenJWT: String, cachedEmail: String?) -> CursorIDEIdentity? {
        guard let claims = JWTClaims.decode(jwt: accessTokenJWT),
              let subject = normalizedSubject(claims.subject)
        else {
            return nil
        }
        return CursorIDEIdentity(subject: subject, email: cachedEmail.flatMap(Email.init))
    }

    public static func verify(observed: CursorIDEIdentity, expectedSubject: String) -> Bool {
        guard let expected = normalizedSubject(expectedSubject) else { return false }
        return observed.subject == expected
    }

    fileprivate static func normalizedSubject(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    fileprivate static func normalizedEmail(_ email: Email) -> String {
        email.value.lowercased()
    }
}

/// Matches shared-DB identity to Keychain seats. Path/sidecar never participate.
public enum CursorIDEIdentityMatcher {
    /// Subject wins. Email fallback only when subject matches nobody and exactly one seat email matches.
    /// Ambiguous or empty matches return nil.
    public static func matchingSeat(
        identity: CursorIDEIdentity,
        roster: [StoredSeatRecord]
    ) -> SeatID? {
        let subjectMatches = roster.compactMap { record -> SeatID? in
            guard case .subject(let subject) = record.identity else { return nil }
            guard CursorIDEIdentity.normalizedSubject(subject) == identity.subject else { return nil }
            return record.seatID
        }
        if subjectMatches.count == 1 {
            return subjectMatches[0]
        }
        if subjectMatches.count > 1 {
            return nil
        }

        guard let observedEmail = identity.email else { return nil }
        let normalized = CursorIDEIdentity.normalizedEmail(observedEmail)
        let emailMatches = roster.compactMap { record -> SeatID? in
            guard let seatEmail = record.email else { return nil }
            guard CursorIDEIdentity.normalizedEmail(seatEmail) == normalized else { return nil }
            return record.seatID
        }
        if emailMatches.count == 1 {
            return emailMatches[0]
        }
        return nil
    }
}

extension CursorIDEIdentity: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "CursorIDEIdentity(subject: <redacted>, email: \(email?.value ?? "nil"))"
    }

    public var debugDescription: String { description }
}
