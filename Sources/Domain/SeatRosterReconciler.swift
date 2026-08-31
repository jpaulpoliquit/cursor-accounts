import Foundation

/// Launch-time roster hygiene for CursorBar-owned seats only.
/// Dedupes by stable JWT subject then email. Quarantines incomplete bindings.
public enum SeatRosterReconciler {
    public struct Plan: Sendable, Equatable {
        public let keep: [StoredSeatRecord]
        public let quarantineSeatIDs: [SeatID]

        public init(keep: [StoredSeatRecord], quarantineSeatIDs: [SeatID]) {
            self.keep = keep
            self.quarantineSeatIDs = quarantineSeatIDs
        }
    }

    public static func plan(roster: [StoredSeatRecord]) -> Plan {
        var bestByKey: [String: StoredSeatRecord] = [:]
        var quarantine = Set<SeatID>()

        let ordered = roster.sorted { $0.seatID.displayIndex < $1.seatID.displayIndex }
        for record in ordered {
            let key = identityKey(record.identity)
            if let existing = bestByKey[key] {
                let winner = prefer(existing, record)
                let loser = winner.seatID == existing.seatID ? record : existing
                bestByKey[key] = winner
                quarantine.insert(loser.seatID)
            } else {
                bestByKey[key] = record
            }
        }

        var keep: [StoredSeatRecord] = []
        for record in bestByKey.values.sorted(by: { $0.seatID.displayIndex < $1.seatID.displayIndex }) {
            if record.hasUsablePresentationIdentity {
                keep.append(record)
            } else {
                quarantine.insert(record.seatID)
            }
        }

        // Never quarantine a seat that remains in keep (dedupe edge).
        let keepIDs = Set(keep.map(\.seatID))
        quarantine.subtract(keepIDs)
        return Plan(
            keep: keep,
            quarantineSeatIDs: quarantine.sorted()
        )
    }

    private static func identityKey(_ identity: SessionIdentity) -> String {
        switch identity {
        case .subject(let subject):
            return "sub:\(subject)"
        case .email(let email):
            return "email:\(email.value.lowercased())"
        }
    }

    private static func prefer(_ a: StoredSeatRecord, _ b: StoredSeatRecord) -> StoredSeatRecord {
        switch (a.hasUsablePresentationIdentity, b.hasUsablePresentationIdentity) {
        case (true, false):
            return a
        case (false, true):
            return b
        default:
            return a.seatID.displayIndex <= b.seatID.displayIndex ? a : b
        }
    }
}

extension StoredSeatRecord {
    /// Connected presentation requires email or display name, not subject-only JWT binding.
    public var hasUsablePresentationIdentity: Bool {
        email != nil || displayName != nil
    }
}
