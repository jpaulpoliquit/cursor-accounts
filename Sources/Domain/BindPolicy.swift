import Foundation

/// Pure roster placement for an imported desktop identity.
public struct BindDecision: Sendable, Equatable {
    public let seatID: SeatID
    public let writeTokens: Bool

    public init(seatID: SeatID, writeTokens: Bool) {
        self.seatID = seatID
        self.writeTokens = writeTokens
    }
}

public enum BindPolicy {
    /// Idempotent placement. Same identity keeps its seat. New identity takes the next unused key.
    public static func decide(
        importedIdentity: SessionIdentity,
        importedExpiresAt: Date?,
        roster: [StoredSeatRecord],
        storedProbeSucceeded: Bool
    ) -> BindDecision {
        if let existing = roster.first(where: { $0.identity == importedIdentity }) {
            let writeTokens = shouldWriteTokens(
                importedExpiresAt: importedExpiresAt,
                storedExpiresAt: existing.expiresAt,
                storedProbeSucceeded: storedProbeSucceeded
            )
            return BindDecision(seatID: existing.seatID, writeTokens: writeTokens)
        }

        let occupied = Set(roster.map(\.seatID))
        return BindDecision(seatID: SeatID.next(occupied: occupied), writeTokens: true)
    }

    /// Update imported tokens only when stored probe failed or imported exp is newer/equal.
    public static func shouldWriteTokens(
        importedExpiresAt: Date?,
        storedExpiresAt: Date?,
        storedProbeSucceeded: Bool
    ) -> Bool {
        if !storedProbeSucceeded { return true }
        switch (importedExpiresAt, storedExpiresAt) {
        case let (imported?, stored?):
            return imported >= stored
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return true
        }
    }
}
