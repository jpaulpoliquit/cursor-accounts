import CursorBarDomain
import Foundation

public protocol SeatCredentialStore: Sendable {
    func loadAll() throws -> [StoredSeatRecord]
    func load(seatID: SeatID) throws -> StoredSeatRecord?
    func save(_ record: StoredSeatRecord) throws
    func delete(seatID: SeatID) throws
}

extension SeatKeychainStore: SeatCredentialStore {}
