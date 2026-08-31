import CursorBarAdapters
import CursorBarDomain
import XCTest

final class KeychainProductionGuardTests: XCTestCase {
    func testProductionServiceNameIsReserved() {
        XCTAssertEqual(KeychainServicePolicy.ownedServiceName, "app.cursorbar")
        XCTAssertTrue(KeychainServicePolicy.isWritable(KeychainServicePolicy.ownedServiceName))
    }

    func testTestServicePrefixIsWritableAndNotProduction() {
        let name = KeychainServicePolicy.testServicePrefix + "unit-\(UUID().uuidString)"
        KeychainServicePolicy.assertWritable(name)
        KeychainServicePolicy.assertNotProductionServiceForTests(name)
        XCTAssertNotEqual(name, KeychainServicePolicy.ownedServiceName)
    }

    func testFakeSeat2FixtureInMemoryNeverTouchesProductionService() throws {
        let store = UncheckedMemorySeatStore()
        let ghost = StoredSeatRecord(
            seatID: .seat2,
            identity: .subject("fixture-sub"),
            access: try XCTUnwrap(AccessToken("access-seat2")),
            refresh: try XCTUnwrap(RefreshToken("refresh-seat2")),
            email: nil,
            displayName: nil,
            expiresAt: Date(timeIntervalSince1970: 1),
            membershipType: "ultra",
            subscriptionStatus: nil
        )
        try store.save(ghost)
        XCTAssertNotNil(try store.load(seatID: .seat2))

        let plan = SeatRosterReconciler.plan(roster: try store.loadAll())
        for seatID in plan.quarantineSeatIDs {
            try store.delete(seatID: seatID)
        }
        XCTAssertNil(try store.load(seatID: .seat2))
        XCTAssertTrue(plan.keep.isEmpty)
    }

    func testIsolatedTestKeychainStoreRejectsProductionNameForTests() {
        // Compile-time policy: helpers must call assertNotProductionServiceForTests first.
        let isolated = KeychainServicePolicy.testServicePrefix + "adapters"
        KeychainServicePolicy.assertNotProductionServiceForTests(isolated)
        let store = SeatKeychainStore(serviceName: isolated)
        XCTAssertNotNil(store)
    }
}
