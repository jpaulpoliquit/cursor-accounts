import CursorBarAdapters
import CursorBarDomain
import XCTest

final class OwnedKeychainMigratorTests: XCTestCase {
    func testRepairNotNeededWhenProbeAllows() throws {
        let store = UncheckedMemorySeatStore()
        try store.save(Self.sampleRecord(seatID: .seat1))
        let migrator = OwnedKeychainMigrator(store: store, probeDenied: { false })
        XCTAssertEqual(migrator.repairIfNeeded(), .notNeeded)
        XCTAssertNotNil(try store.load(seatID: .seat1))
    }

    func testRepairDeletesOwnedSeatsWhenProbeDenied() throws {
        let store = UncheckedMemorySeatStore()
        try store.save(Self.sampleRecord(seatID: .seat1))
        try store.save(Self.sampleRecord(seatID: .seat2))
        let migrator = OwnedKeychainMigrator(store: store, probeDenied: { true })
        let outcome = migrator.repairIfNeeded()
        guard case .repaired(let deleted) = outcome else {
            return XCTFail("expected repaired, got \(outcome)")
        }
        XCTAssertEqual(Set(deleted), [.seat1, .seat2])
        XCTAssertNil(try store.load(seatID: .seat1))
        XCTAssertNil(try store.load(seatID: .seat2))
    }

    func testAccessDeniedStatusesAreClassified() {
        let denied = OwnedKeychainAccess.ProbeResult.accessDenied(errSecInteractionNotAllowed)
        XCTAssertEqual(denied, .accessDenied(errSecInteractionNotAllowed))
        XCTAssertNotEqual(OwnedKeychainAccess.ProbeResult.missing, .readable)
    }

    private static func sampleRecord(seatID: SeatID) -> StoredSeatRecord {
        StoredSeatRecord(
            seatID: seatID,
            identity: .subject("auth-\(seatID.rawValue)"),
            access: AccessToken("access-token-\(seatID.rawValue)")!,
            refresh: RefreshToken("refresh-token-\(seatID.rawValue)")!,
            email: nil,
            displayName: DisplayName("seat"),
            expiresAt: Date(timeIntervalSince1970: 9_999_999),
            membershipType: "ultra",
            subscriptionStatus: nil
        )
    }
}
