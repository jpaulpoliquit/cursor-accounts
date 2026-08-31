import CursorBarDomain
import XCTest

final class FocusedSeatPolicyTests: XCTestCase {
    func testKeepsStoredWhenPresent() {
        XCTAssertEqual(
            FocusedSeatPolicy.resolve(stored: .seat3, roster: [.seat2, .seat3, .seat4]),
            .seat3
        )
    }

    func testSnapsMissingStoredToFirstRosterSeat() {
        XCTAssertEqual(
            FocusedSeatPolicy.resolve(stored: .seat1, roster: [.seat2, SeatID(rawValue: "seat6")!]),
            .seat2
        )
    }

    func testEmptyRosterKeepsStored() {
        XCTAssertEqual(
            FocusedSeatPolicy.resolve(stored: .seat4, roster: []),
            .seat4
        )
    }
}
