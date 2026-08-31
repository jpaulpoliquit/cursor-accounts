import CursorBarDomain
import XCTest

final class DashboardAccountOrderingTests: XCTestCase {
    func testResetSoonPutsEarliestDateFirstAndNilLast() {
        let soon = seat(.seat1, name: "Soon", reset: Date(timeIntervalSince1970: 100))
        let later = seat(.seat2, name: "Later", reset: Date(timeIntervalSince1970: 400))
        let none = seat(.seat3, name: "None", reset: nil)
        let sorted = DashboardAccountOrdering.sorted(
            [later, none, soon],
            by: .reset,
            direction: .ascending
        )
        XCTAssertEqual(sorted.map(\.seatID), [.seat1, .seat2, .seat3])
    }

    func testActiveSortPutsDesktopBoundFirstWhenDescending() {
        let idle = seat(.seat1, name: "Idle", bound: false)
        let active = seat(.seat2, name: "Live", bound: true)
        let sorted = DashboardAccountOrdering.sorted(
            [idle, active],
            by: .active,
            direction: DashboardAccountSort.active.defaultDirection
        )
        XCTAssertEqual(sorted.map(\.seatID), [.seat2, .seat1])
    }

    func testUsageSortUsesHighestPercentAndPutsMissingLast() {
        let high = seat(.seat1, name: "High", auto: 90, api: 10)
        let low = seat(.seat2, name: "Low", auto: 12, api: 8)
        let missing = seat(.seat3, name: "Empty")
        let sorted = DashboardAccountOrdering.sorted(
            [low, missing, high],
            by: .usage,
            direction: .descending
        )
        XCTAssertEqual(sorted.map(\.seatID), [.seat1, .seat2, .seat3])
    }

    func testNameSortIsAlphabetical() {
        let b = seat(.seat1, name: "beta")
        let a = seat(.seat2, name: "alpha")
        let sorted = DashboardAccountOrdering.sorted([b, a], by: .name, direction: .ascending)
        XCTAssertEqual(sorted.map(\.dashboardTitle), ["alpha", "beta"])
    }

    func testTappingSameSortTogglesDirection() {
        let next = DashboardAccountOrdering.nextSelection(
            current: .reset,
            direction: .ascending,
            tapped: .reset
        )
        XCTAssertEqual(next.0, .reset)
        XCTAssertEqual(next.1, .descending)
    }

    func testTappingOtherSortUsesDefaultDirection() {
        let next = DashboardAccountOrdering.nextSelection(
            current: .name,
            direction: .ascending,
            tapped: .reset
        )
        XCTAssertEqual(next.0, .reset)
        XCTAssertEqual(next.1, .ascending)
    }

    private func seat(
        _ id: SeatID,
        name: String,
        reset: Date? = nil,
        bound: Bool = false,
        auto: Double? = nil,
        api: Double? = nil
    ) -> SeatPresentation {
        SeatPresentation(
            seatID: id,
            label: .displayName(DisplayName(name)!),
            auth: .signedIn,
            resetDate: reset,
            autoPercent: auto.map { PercentUsed(unchecked: $0) },
            apiPercent: api.map { PercentUsed(unchecked: $0) },
            isDesktopBound: bound,
            identityPolicy: .maskEmail
        )
    }
}
