import CursorBarDomain
import XCTest

final class DashboardAccountFilterTests: XCTestCase {
    func testEmptyQueryKeepsEverySeat() {
        let seats = [seat(.seat1, name: "Ada"), seat(.seat2, name: "Bea")]
        XCTAssertEqual(DashboardAccountFilter.apply(seats, query: "  ").map(\.seatID), [.seat1, .seat2])
    }

    func testNameAndPlanAndTeamMatch() {
        let personal = seat(.seat1, name: "john 4", plan: "Ultra")
        let team = SeatPresentation(
            seatID: .seat2,
            label: .displayName(DisplayName("John (Community Software)")!),
            auth: .signedIn,
            planName: "Team",
            planOwner: .team,
            identityPolicy: .revealEmail
        )
        XCTAssertTrue(DashboardAccountFilter.matches(personal, query: "JOHN"))
        XCTAssertTrue(DashboardAccountFilter.matches(personal, query: "ultra"))
        XCTAssertTrue(DashboardAccountFilter.matches(team, query: "team"))
        XCTAssertFalse(DashboardAccountFilter.matches(personal, query: "community"))
        let teamOnly = SeatPresentation(
            seatID: .seat4,
            label: .displayName(DisplayName("Bo")!),
            auth: .signedIn,
            planOwner: .team,
            identityPolicy: .revealEmail
        )
        XCTAssertTrue(DashboardAccountFilter.matches(teamOnly, query: "team"))
        XCTAssertFalse(DashboardAccountFilter.matches(teamOnly, query: "t"))
        XCTAssertFalse(DashboardAccountFilter.matches(teamOnly, query: "e"))
        XCTAssertFalse(DashboardAccountFilter.matches(teamOnly, query: "a"))
        XCTAssertEqual(
            DashboardAccountFilter.apply([personal, team], query: "community").map(\.seatID),
            [.seat2]
        )
    }

    func testRevealedEmailMatches() {
        let seat = SeatPresentation(
            seatID: .seat3,
            label: .displayName(DisplayName("Ada")!),
            revealedEmail: Email("ada@example.com")!,
            auth: .signedIn,
            identityPolicy: .revealEmail
        )
        XCTAssertTrue(DashboardAccountFilter.matches(seat, query: "ada@"))
        XCTAssertFalse(DashboardAccountFilter.matches(seat, query: "zzz"))
    }

    func testEmptyReasonDistinguishesRosterFromFilter() {
        let seats = [seat(.seat1, name: "Ada")]
        XCTAssertEqual(
            DashboardAccountFilter.Listing.make(seats: [], query: "").emptyReason,
            .noAccountsConnected
        )
        XCTAssertEqual(
            DashboardAccountFilter.Listing.make(seats: [], query: "zzz").emptyReason,
            .noAccountsConnected
        )
        XCTAssertEqual(
            DashboardAccountFilter.Listing.make(seats: seats, query: "zzz").emptyReason,
            .noFilterMatches
        )
        XCTAssertEqual(
            DashboardAccountFilter.Listing.make(seats: seats, query: "zzz").emptyReason?.message,
            "No accounts match this filter"
        )
        XCTAssertNil(DashboardAccountFilter.Listing.make(seats: seats, query: "Ada").emptyReason)
    }

    private func seat(_ id: SeatID, name: String, plan: String? = nil) -> SeatPresentation {
        SeatPresentation(
            seatID: id,
            label: .displayName(DisplayName(name)!),
            auth: .signedIn,
            planName: plan,
            identityPolicy: .maskEmail
        )
    }
}
