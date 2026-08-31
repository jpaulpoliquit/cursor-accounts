import CursorBarDomain
import XCTest

final class SeatRosterReconcilerTests: XCTestCase {
    func testSubjectOnlySeatIsQuarantined() throws {
        let ghost = try record(
            seat: .seat2,
            identity: .subject("ghost-sub"),
            email: nil,
            displayName: nil
        )
        let plan = SeatRosterReconciler.plan(roster: [ghost])
        XCTAssertTrue(plan.keep.isEmpty)
        XCTAssertEqual(plan.quarantineSeatIDs, [.seat2])
        XCTAssertFalse(ghost.hasUsablePresentationIdentity)
    }

    func testUsableSeat1SurvivesWhenGhostSeat2Quarantined() throws {
        let seat1 = try record(
            seat: .seat1,
            identity: .subject("real-sub"),
            email: Email("user@example.com"),
            displayName: DisplayName("john 5")
        )
        let seat2 = try record(
            seat: .seat2,
            identity: .subject("other-sub"),
            email: nil,
            displayName: nil
        )
        let plan = SeatRosterReconciler.plan(roster: [seat1, seat2])
        XCTAssertEqual(plan.keep.map(\.seatID), [.seat1])
        XCTAssertEqual(plan.quarantineSeatIDs, [.seat2])
    }

    func testDuplicateSubjectCollapsesToOneSeat() throws {
        let first = try record(
            seat: .seat1,
            identity: .subject("same-sub"),
            email: Email("a@example.com"),
            displayName: nil
        )
        let duplicate = try record(
            seat: .seat3,
            identity: .subject("same-sub"),
            email: nil,
            displayName: DisplayName("kept")
        )
        let plan = SeatRosterReconciler.plan(roster: [first, duplicate])
        XCTAssertEqual(plan.keep.count, 1)
        // Both usable; keep lower SeatID.
        XCTAssertEqual(plan.keep[0].seatID, .seat1)
        XCTAssertEqual(Set(plan.quarantineSeatIDs), [.seat3])
    }

    func testDuplicatePrefersUsableIdentityOverSubjectOnly() throws {
        let incomplete = try record(
            seat: .seat1,
            identity: .subject("same-sub"),
            email: nil,
            displayName: nil
        )
        let complete = try record(
            seat: .seat3,
            identity: .subject("same-sub"),
            email: nil,
            displayName: DisplayName("kept")
        )
        let plan = SeatRosterReconciler.plan(roster: [incomplete, complete])
        XCTAssertEqual(plan.keep.map(\.seatID), [.seat3])
        XCTAssertEqual(plan.quarantineSeatIDs, [.seat1])
    }

    func testConnectedCountIgnoresSubjectOnlyPresentation() {
        let ghost = SeatPresentation(
            seatID: .seat2,
            label: .cursorAccount(disambiguator: nil),
            auth: .signedIn,
            planName: "ultra",
            identityPolicy: .maskEmail,
            hasUsableIdentity: false
        )
        let real = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            identityPolicy: .maskEmail,
            hasUsableIdentity: true
        )
        XCTAssertFalse(AddAccountPresentation.isConnectedAccount(ghost))
        XCTAssertTrue(AddAccountPresentation.isConnectedAccount(real))
        let seats = [SeatID.seat1, .seat2, .seat3, .seat4, .seat5].map { id -> SeatPresentation in
            if id == .seat1 { return real }
            if id == .seat2 { return ghost }
            return SeatPresentation(
                seatID: id,
                label: .cursorAccount(disambiguator: nil),
                auth: .signedOut,
                identityPolicy: .maskEmail
            )
        }
        let add = AddAccountPresentation.project(from: seats)
        guard case .available(let title, _) = add else {
            return XCTFail("expected connect another")
        }
        XCTAssertEqual(title, "Connect another account")
        XCTAssertEqual(seats.filter(AddAccountPresentation.isConnectedAccount).count, 1)
    }

    private func record(
        seat: SeatID,
        identity: SessionIdentity,
        email: Email?,
        displayName: DisplayName?
    ) throws -> StoredSeatRecord {
        StoredSeatRecord(
            seatID: seat,
            identity: identity,
            access: try XCTUnwrap(AccessToken("access-\(seat.rawValue)")),
            refresh: try XCTUnwrap(RefreshToken("refresh-\(seat.rawValue)")),
            email: email,
            displayName: displayName,
            expiresAt: Date(timeIntervalSince1970: 9_999_999),
            membershipType: nil,
            subscriptionStatus: nil
        )
    }
}
