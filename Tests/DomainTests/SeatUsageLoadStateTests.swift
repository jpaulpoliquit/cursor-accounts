import CursorBarDomain
import XCTest

final class SeatUsageLoadStateTests: XCTestCase {
    func testPendingWhenRefreshingWithoutSnapshot() {
        let state = SeatUsageLoadState.resolve(
            auth: .signedIn,
            hasSnapshot: false,
            refreshPhase: .refreshing(.all),
            seatID: .seat1
        )
        XCTAssertEqual(state, .pending)
    }

    func testFailedWhenSettledWithoutSnapshot() {
        let state = SeatUsageLoadState.resolve(
            auth: .signedIn,
            hasSnapshot: false,
            refreshPhase: .settled(
                UsageRefreshReport(
                    outcomes: [.seat1: .failed(message: "Denied")],
                    bindingEpochs: [.seat1: 0]
                )
            ),
            seatID: .seat1
        )
        XCTAssertEqual(state, .failed)
    }

    func testReadyWhenSnapshotExists() {
        let state = SeatUsageLoadState.resolve(
            auth: .signedIn,
            hasSnapshot: true,
            refreshPhase: .idle,
            seatID: .seat1
        )
        XCTAssertEqual(state, .ready)
    }
}
