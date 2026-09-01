import CursorBarDomain
import XCTest

final class SeatUserLabelTests: XCTestCase {
    func testRejectsEmptyAtSignAndOverflow() {
        XCTAssertNil(SeatUserLabel(""))
        XCTAssertNil(SeatUserLabel("   "))
        XCTAssertNil(SeatUserLabel("work@home"))
        XCTAssertNil(SeatUserLabel(String(repeating: "a", count: SeatUserLabel.maxCharacters + 1)))
        XCTAssertEqual(SeatUserLabel(" Work ")?.value, "Work")
        XCTAssertEqual(SeatUserLabel(String(repeating: "b", count: SeatUserLabel.maxCharacters))?.value.count, 40)
        XCTAssertNil(SeatUserLabel.rejectionReason("Work"))
        XCTAssertNil(SeatUserLabel.rejectionReason("   "))
        XCTAssertEqual(SeatUserLabel.rejectionReason("work@home"), "Labels cannot contain @")
        XCTAssertEqual(
            SeatUserLabel.rejectionReason(String(repeating: "a", count: SeatUserLabel.maxCharacters + 1)),
            "Keep labels under \(SeatUserLabel.maxCharacters) characters"
        )
    }

    func testPrimaryPrefersNickname() {
        let identity = AccountLabel.displayName(DisplayName("john 5")!)
        XCTAssertEqual(
            SeatUserLabelResolver.primary(userLabel: SeatUserLabel("Work"), identity: identity),
            "Work"
        )
        XCTAssertEqual(SeatUserLabelResolver.primary(userLabel: nil, identity: identity), "john 5")
    }

    func testTargetPrefersUniqueLabelThenSeatID() {
        let work = makeSeat(.seat1, label: "Work", name: "john 5")
        let home = makeSeat(.seat2, label: nil, name: "Ada")
        XCTAssertEqual(AgentSeatTarget.resolve(query: "work", seats: [work, home]), .seat1)
        XCTAssertEqual(AgentSeatTarget.resolve(query: "seat2", seats: [work, home]), .seat2)
        XCTAssertEqual(AgentSeatTarget.resolve(query: "Ada", seats: [work, home]), .seat2)
        XCTAssertNil(AgentSeatTarget.resolve(query: "missing", seats: [work, home]))
    }

    func testAmbiguousLabelsFailClosed() {
        let a = makeSeat(.seat1, label: "Work", name: "A")
        let b = makeSeat(.seat2, label: "Work", name: "B")
        XCTAssertNil(AgentSeatTarget.resolve(query: "Work", seats: [a, b]))
        XCTAssertEqual(AgentSeatTarget.resolve(query: "seat1", seats: [a, b]), .seat1)
    }

    func testTargetMatchesEmailWhenIdentityIsMasked() {
        let work = makeSeat(.seat1, label: "Work", name: "john 5")
        XCTAssertNil(work.revealedEmail)
        let email = Email("jp@example.com")!
        XCTAssertEqual(
            AgentSeatTarget.resolve(query: "jp@example.com", seats: [work], emails: [.seat1: email]),
            .seat1
        )
        XCTAssertNil(AgentSeatTarget.resolve(query: "jp@example.com", seats: [work]))
    }

    private func makeSeat(_ id: SeatID, label: String?, name: String) -> SeatPresentation {
        SeatPresentation(
            seatID: id,
            label: .displayName(DisplayName(name)!),
            auth: .signedIn,
            identityPolicy: .maskEmail,
            userLabel: label.flatMap(SeatUserLabel.init)
        )
    }
}
