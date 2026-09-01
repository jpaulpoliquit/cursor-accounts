import Foundation

/// User-assigned nickname. Distinct from Cursor display name and email.
public struct SeatUserLabel: Hashable, Codable, Sendable {
    public static let maxCharacters = 40

    public let value: String

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains("@") else { return nil }
        guard trimmed.count <= Self.maxCharacters else { return nil }
        self.value = trimmed
    }

    public static func rejectionReason(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("@") { return "Labels cannot contain @" }
        if trimmed.count > maxCharacters {
            return "Keep labels under \(maxCharacters) characters"
        }
        return Self(trimmed) == nil ? "Invalid label" : nil
    }
}

/// Primary title prefers a nickname; identity stays available as secondary text.
public enum SeatUserLabelResolver {
    public static func primary(userLabel: SeatUserLabel?, identity: AccountLabel) -> String {
        userLabel?.value ?? identity.text
    }
}

/// Resolve a CLI/menu query to one connected seat. Ambiguous matches fail closed.
public enum AgentSeatTarget {
    public static func resolve(
        query: String,
        seats: [SeatPresentation],
        emails: [SeatID: Email] = [:]
    ) -> SeatID? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let id = SeatID(rawValue: needle), seats.contains(where: { $0.seatID == id }) {
            return id
        }
        let byLabel = seats.filter {
            $0.userLabel?.value.caseInsensitiveCompare(needle) == .orderedSame
        }
        if byLabel.count == 1 { return byLabel[0].seatID }
        if byLabel.count > 1 { return nil }
        let byTitle = seats.filter {
            $0.dashboardTitle.caseInsensitiveCompare(needle) == .orderedSame
        }
        if byTitle.count == 1 { return byTitle[0].seatID }
        if byTitle.count > 1 { return nil }
        let byEmail = seats.filter { seat in
            if let revealed = seat.revealedEmail,
               revealed.value.caseInsensitiveCompare(needle) == .orderedSame
            {
                return true
            }
            if let email = emails[seat.seatID],
               email.value.caseInsensitiveCompare(needle) == .orderedSame
            {
                return true
            }
            return false
        }
        if byEmail.count == 1 { return byEmail[0].seatID }
        return nil
    }
}
