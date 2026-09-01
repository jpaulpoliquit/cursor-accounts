import CursorBarAdapters
import CursorBarDomain
import XCTest

final class SeatUserLabelStoreTests: XCTestCase {
    func testRoundTripFollowsIdentityAcrossSeats() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("seat-labels-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SeatUserLabelStore(applicationSupportRoot: root)
        let identity = SessionIdentity.subject("user-sub")
        store.set(label: SeatUserLabel("Work"), identity: identity, seatID: .seat1)
        XCTAssertEqual(store.labelsBySeat()[.seat1]?.value, "Work")

        let moved = StoredSeatRecord(
            seatID: .seat3,
            identity: identity,
            access: try XCTUnwrap(AccessToken("access-1")),
            refresh: try XCTUnwrap(RefreshToken("refresh-1")),
            email: Email("a@b.com"),
            expiresAt: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )
        XCTAssertEqual(store.labels(for: [moved])[.seat3]?.value, "Work")

        store.set(label: nil, identity: identity, seatID: .seat3)
        XCTAssertEqual(store.labelsBySeat(), [:])
        let data = try Data(contentsOf: root.appendingPathComponent("seat-user-labels.json"))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("access"))
        XCTAssertFalse(json.contains("Work"))
    }

    func testLabelFollowsEmailAcrossSeatAndSubject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("seat-labels-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SeatUserLabelStore(applicationSupportRoot: root)
        let email = try XCTUnwrap(Email("jp@example.com"))
        store.set(
            label: SeatUserLabel("Work"),
            identity: .subject("old-sub"),
            email: email,
            seatID: .seat1
        )
        let remapped = StoredSeatRecord(
            seatID: .seat4,
            identity: .subject("new-sub"),
            access: try XCTUnwrap(AccessToken("access-1")),
            refresh: try XCTUnwrap(RefreshToken("refresh-1")),
            email: email,
            expiresAt: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )
        XCTAssertEqual(store.labels(for: [remapped])[.seat4]?.value, "Work")
        XCTAssertEqual(
            store.labels(seatIDs: [.seat4], emails: [.seat4: email])[.seat4]?.value,
            "Work"
        )
    }
}
