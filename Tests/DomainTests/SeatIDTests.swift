import CursorBarDomain
import XCTest

final class SeatIDTests: XCTestCase {
    func testFirstEmptyKeepsPreferredWhenFree() {
        XCTAssertEqual(
            SeatID.firstEmpty(preferred: .seat2, isOccupied: { _ in false }),
            .seat2
        )
    }

    func testFirstEmptySkipsOccupiedPreferred() {
        XCTAssertEqual(
            SeatID.firstEmpty(preferred: .seat1, isOccupied: { $0 == .seat1 }),
            .seat2
        )
    }

    func testFirstEmptySkipsAHoleThenGrows() {
        let occupied: Set<SeatID> = [.seat1, .seat2]
        XCTAssertEqual(
            SeatID.firstEmpty(preferred: .seat1, isOccupied: { occupied.contains($0) }),
            .seat3
        )
    }
}
