import CursorBarDomain
import Foundation

/// One-time repair when `app.cursorbar` items were created under a stale designated
/// requirement (ad-hoc CDHash). Deletes only owned items, then caller reimports.
public struct OwnedKeychainMigrator: Sendable {
    public enum Outcome: Sendable, Equatable {
        case notNeeded
        case repaired(deletedSeats: [SeatID])
        case failed(message: String)
    }

    public typealias ProbeDenied = @Sendable () -> Bool

    private let store: any SeatCredentialStore
    private let probeDenied: ProbeDenied

    public init(
        store: any SeatCredentialStore = SeatKeychainStore(),
        probeDenied: @escaping ProbeDenied = { OwnedKeychainAccess.anySeatAccessDenied() }
    ) {
        self.store = store
        self.probeDenied = probeDenied
    }

    public func repairIfNeeded() -> Outcome {
        guard probeDenied() else { return .notNeeded }

        let roster: [StoredSeatRecord]
        do {
            roster = try store.loadAll()
        } catch {
            return .failed(
                message: "Stale Keychain ACL blocked repair. Remove only app.cursorbar items in Keychain Access, then relaunch."
            )
        }
        var deleted: [SeatID] = []
        for record in roster {
            do {
                try store.delete(seatID: record.seatID)
                deleted.append(record.seatID)
            } catch {
                return .failed(
                    message: "Stale Keychain ACL blocked repair. Remove only app.cursorbar items in Keychain Access, then relaunch."
                )
            }
        }
        return .repaired(deletedSeats: deleted)
    }
}
