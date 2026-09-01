import CursorBarAdapters
import CursorBarDomain
import XCTest

final class PublicRosterStoreTests: XCTestCase {
    func testRoundTripOmitsTokens() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("public-roster-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PublicRosterStore(applicationSupportRoot: root)
        let seat = SeatSnapshot(
            seatID: .seat1,
            auth: .signedIn,
            displayName: DisplayName("john 5"),
            plan: PlanInfo(name: "ultra")
        )
        store.write(
            aggregate: AggregateSnapshot(seats: [seat]),
            userLabels: [.seat1: SeatUserLabel("Work")!],
            desktopBoundSeatID: .seat1
        )
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.seats.first?.displayName?.value, "john 5")
        XCTAssertEqual(loaded.userLabels["seat1"], "Work")
        XCTAssertEqual(loaded.desktopBoundSeatID, "seat1")
        let json = try XCTUnwrap(String(data: Data(contentsOf: root.appendingPathComponent("public-roster.json")), encoding: .utf8))
        XCTAssertFalse(json.contains("accessToken"))
        XCTAssertFalse(json.contains("Bearer"))
    }

    func testMarkDesktopBoundKeepsSeatsAndLabels() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("public-roster-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PublicRosterStore(applicationSupportRoot: root)
        let seats = [
            SeatSnapshot(seatID: .seat1, auth: .signedIn, displayName: DisplayName("one")),
            SeatSnapshot(seatID: .seat2, auth: .signedIn, displayName: DisplayName("two")),
        ]
        store.write(
            aggregate: AggregateSnapshot(seats: seats),
            userLabels: [.seat1: SeatUserLabel("Work")!],
            desktopBoundSeatID: .seat1
        )
        store.markDesktopBound(.seat2)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.desktopBoundSeatID, "seat2")
        XCTAssertEqual(loaded.seats.map(\.seatID), [.seat1, .seat2])
        XCTAssertEqual(loaded.userLabels["seat1"], "Work")
    }
}
