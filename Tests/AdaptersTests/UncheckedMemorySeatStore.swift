import CursorBarAdapters
import CursorBarDomain
import Foundation

final class UncheckedMemorySeatStore: SeatCredentialStore, @unchecked Sendable {
    private var records: [SeatID: StoredSeatRecord]
    private let lock = NSLock()

    init(records: [StoredSeatRecord] = []) {
        var map: [SeatID: StoredSeatRecord] = [:]
        for record in records {
            map[record.seatID] = record
        }
        self.records = map
    }

    func loadAll() throws -> [StoredSeatRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records.values.sorted { $0.seatID < $1.seatID }
    }

    func load(seatID: SeatID) throws -> StoredSeatRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records[seatID]
    }

    func save(_ record: StoredSeatRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        records[record.seatID] = record
    }

    func delete(seatID: SeatID) throws {
        lock.lock()
        defer { lock.unlock() }
        records[seatID] = nil
    }
}
