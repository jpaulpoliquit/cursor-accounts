import CursorBarDomain
import XCTest

final class AddAccountPresentationTests: XCTestCase {
    func testZeroConnectedShowsConnectCursorAccount() {
        let seats: [SeatPresentation] = []
        let add = AddAccountPresentation.project(from: seats)
        guard case .available(let title, let seatID) = add else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(title, "Connect Cursor account")
        XCTAssertEqual(seatID, .seat1)
        XCTAssertEqual(add.accessibilityLabel, "Connect Cursor account")
    }

    func testOneConnectedShowsConnectAnother() {
        let seats = makeRoster(connected: [.seat1])
        let add = AddAccountPresentation.project(from: seats)
        guard case .available(let title, let seatID) = add else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(title, "Connect another account")
        XCTAssertEqual(seatID, .seat2)
        XCTAssertEqual(add.accessibilityLabel, "Connect another Cursor account")
    }

    func testFourConnectedTargetsFifth() {
        let seats = makeRoster(connected: [.seat1, .seat2, .seat3, .seat4])
        let add = AddAccountPresentation.project(from: seats)
        guard case .available(_, let seatID) = add else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(seatID, .seat5)
    }

    func testFiveConnectedStillOffersNext() {
        let seats = makeRoster(connected: [.seat1, .seat2, .seat3, .seat4, .seat5])
        let add = AddAccountPresentation.project(from: seats)
        guard case .available(let title, let seatID) = add else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(title, "Connect another account")
        XCTAssertEqual(seatID, SeatID(rawValue: "seat6")!)
    }

    func testInProgressHidesAdditionalConnectCTA() {
        var seats = makeRoster(connected: [.seat1])
        seats = seats.map { seat in
            guard seat.seatID == .seat2 else { return seat }
            return SeatPresentation(
                seatID: .seat2,
                label: .cursorAccount(disambiguator: nil),
                auth: .signingIn,
                loginPhase: .polling,
                identityPolicy: .maskEmail
            )
        }
        let add = AddAccountPresentation.project(from: seats)
        guard case .signingIn(let seatID, let canCancel, let isFinishing) = add else {
            return XCTFail("expected signingIn")
        }
        XCTAssertEqual(seatID, .seat2)
        XCTAssertTrue(canCancel)
        XCTAssertFalse(isFinishing)
    }

    func testFinishingSignInProjectsFinishingChrome() {
        let seats = [SeatID.seat1, .seat2, .seat3, .seat4, .seat5].map { seatID -> SeatPresentation in
            if seatID == .seat2 {
                return SeatPresentation(
                    seatID: .seat2,
                    label: .cursorAccount(disambiguator: nil),
                    auth: .signingIn,
                    loginPhase: .finishingSignIn,
                    identityPolicy: .maskEmail
                )
            }
            return SeatPresentation(
                seatID: seatID,
                label: .cursorAccount(disambiguator: nil),
                auth: .signedOut,
                identityPolicy: .maskEmail
            )
        }
        let add = AddAccountPresentation.project(from: seats)
        guard case .signingIn(_, let canCancel, let isFinishing) = add else {
            return XCTFail("expected signingIn finishing")
        }
        XCTAssertTrue(canCancel)
        XCTAssertTrue(isFinishing)
        XCTAssertEqual(add.menuTitle, "Finishing sign-in…")
        XCTAssertEqual(add.accessibilityLabel, "Finishing Cursor account sign-in")
    }

    func testProjectorEmitsConnectedPlusSingleAdd() {
        let connected = SeatSnapshot(
            seatID: .seat1,
            auth: .signedIn,
            email: Email("user@example.com"),
            displayName: DisplayName("john 5"),
            plan: PlanInfo(name: "ultra"),
            usage: PeriodUsage(
                autoPercentUsed: PercentUsed(unchecked: 10),
                apiPercentUsed: PercentUsed(unchecked: 20),
                totalPercentUsed: PercentUsed(unchecked: 15)
            ),
            onDemand: OnDemandState(mode: .fixed(PositiveDollars(190)!))
        )
        let presentation = SeatPresentationProjector.project(
            aggregate: AggregateSnapshot(seats: [connected]),
            usageBySeat: [:],
            identityPolicy: .maskEmail,
            focusedSeatID: .seat1,
            loginPhases: [:],
            bootstrapPhase: .settled(.kept(.seat1)),
            usageRefreshPhase: .idle,
            setHardLimitPhase: .idle
        )
        XCTAssertEqual(presentation.connectedAccounts.count, 1)
        XCTAssertEqual(presentation.connectedAccounts[0].label.text, "john 5")
        XCTAssertEqual(presentation.signedInCount, 1)
        XCTAssertTrue(presentation.aggregateLine.hasPrefix("1 connected"))
        XCTAssertFalse(presentation.aggregateLine.contains("/5"))
        XCTAssertFalse(presentation.aggregateLine.contains("Seat"))
        guard case .available(let title, let seatID) = presentation.addAccount else {
            return XCTFail("expected one connect CTA")
        }
        XCTAssertEqual(title, "Connect another account")
        XCTAssertEqual(seatID, .seat2)
        XCTAssertFalse(presentation.connectedAccounts.contains(where: { $0.auth == .signedOut }))
    }

    func testFirstAvailableSkipsOccupiedSeats() {
        let seats = makeRoster(connected: [.seat1, .seat3])
        XCTAssertEqual(AddAccountPresentation.firstAvailableSeatID(in: seats), .seat2)
    }

    func testSuccessfulLoginClearsFailedGhosts() {
        XCTAssertEqual(SeatLoginPhase.phases(after: .signedIn(placedOn: .seat2), requested: .seat1), [:])
        XCTAssertEqual(
            SeatLoginPhase.phases(after: .cancelled, requested: .seat3),
            [.seat3: .failed(.cancelled)]
        )
    }

    func testFailedLoginSurfacesOnConnectAndSkipsThatSeat() {
        let seats = [
            SeatPresentation(
                seatID: .seat1,
                label: .cursorAccount(disambiguator: nil),
                auth: .signedOut,
                loginPhase: .failed(.seatNotEmpty),
                identityPolicy: .maskEmail
            )
        ]
        let add = AddAccountPresentation.project(from: seats)
        guard case .failed(let title, let seatID, let message) = add else {
            return XCTFail("expected failed connect chrome")
        }
        XCTAssertEqual(title, "Connect Cursor account")
        XCTAssertEqual(seatID, .seat2)
        XCTAssertEqual(message, "Seat already has an account")
    }

    func testProjectorSurfacesInvisibleSeatNotEmptyOnConnectCard() {
        let presentation = SeatPresentationProjector.project(
            aggregate: .empty,
            usageBySeat: [:],
            identityPolicy: .maskEmail,
            focusedSeatID: .seat1,
            loginPhases: [.seat1: .failed(.seatNotEmpty)],
            bootstrapPhase: .settled(.noDesktopSession),
            usageRefreshPhase: .idle,
            setHardLimitPhase: .idle
        )
        XCTAssertTrue(presentation.connectedAccounts.isEmpty)
        guard case .failed(_, let seatID, let message) = presentation.addAccount else {
            return XCTFail("connect must show the hidden seatNotEmpty failure")
        }
        XCTAssertEqual(seatID, .seat2)
        XCTAssertEqual(message, "Seat already has an account")
    }

    private func makeRoster(connected: [SeatID]) -> [SeatPresentation] {
        [SeatID.seat1, .seat2, .seat3, .seat4, .seat5].map { seatID in
            if connected.contains(seatID) {
                return SeatPresentation(
                    seatID: seatID,
                    label: .displayName(DisplayName("acct \(seatID.displayIndex)")!),
                    auth: .signedIn,
                    identityPolicy: .maskEmail
                )
            }
            return SeatPresentation(
                seatID: seatID,
                label: .cursorAccount(disambiguator: nil),
                auth: .signedOut,
                identityPolicy: .maskEmail
            )
        }
    }
}
