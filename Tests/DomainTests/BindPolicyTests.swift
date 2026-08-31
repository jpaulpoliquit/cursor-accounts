import CursorBarDomain
import XCTest

final class BindPolicyTests: XCTestCase {
    private let subject = SessionIdentity.subject("user-123")
    private let other = SessionIdentity.subject("user-other")

    func testNewIdentityPrefersSeat1WhenEmpty() {
        let decision = BindPolicy.decide(
            importedIdentity: subject,
            importedExpiresAt: Date(timeIntervalSince1970: 200),
            roster: [],
            storedProbeSucceeded: false
        )
        XCTAssertEqual(decision, BindDecision(seatID: .seat1, writeTokens: true))
    }

    func testNewIdentityUsesFirstEmptySeat() throws {
        let roster = [try record(seat: .seat1, identity: other)]
        let decision = BindPolicy.decide(
            importedIdentity: subject,
            importedExpiresAt: Date(timeIntervalSince1970: 200),
            roster: roster,
            storedProbeSucceeded: false
        )
        XCTAssertEqual(decision, BindDecision(seatID: .seat2, writeTokens: true))
    }

    func testSameIdentityKeepsSeatIndex() throws {
        let roster = [
            try record(seat: .seat3, identity: subject, expiresAt: Date(timeIntervalSince1970: 100)),
        ]
        let decision = BindPolicy.decide(
            importedIdentity: subject,
            importedExpiresAt: Date(timeIntervalSince1970: 200),
            roster: roster,
            storedProbeSucceeded: true
        )
        XCTAssertEqual(decision, BindDecision(seatID: .seat3, writeTokens: true))
    }

    func testDoesNotDuplicateIdentityAcrossSeats() throws {
        let roster = [
            try record(seat: .seat1, identity: subject),
            try record(seat: .seat2, identity: other),
        ]
        let decision = BindPolicy.decide(
            importedIdentity: subject,
            importedExpiresAt: nil,
            roster: roster,
            storedProbeSucceeded: true
        )
        XCTAssertEqual(decision, BindDecision(seatID: .seat1, writeTokens: false))
    }

    func testAllocatesNextSeatWhenFiveAreFilled() throws {
        let roster = try [SeatID.seat1, .seat2, .seat3, .seat4, .seat5].map { id in
            try record(seat: id, identity: .subject("user-\(id.rawValue)"))
        }
        let decision = BindPolicy.decide(
            importedIdentity: subject,
            importedExpiresAt: nil,
            roster: roster,
            storedProbeSucceeded: false
        )
        XCTAssertEqual(decision, BindDecision(seatID: SeatID(rawValue: "seat6")!, writeTokens: true))
    }

    func testWriteTokensWhenStoredProbeFails() {
        XCTAssertTrue(
            BindPolicy.shouldWriteTokens(
                importedExpiresAt: Date(timeIntervalSince1970: 50),
                storedExpiresAt: Date(timeIntervalSince1970: 100),
                storedProbeSucceeded: false
            )
        )
    }

    func testKeepTokensWhenStoredProbeOkAndImportedOlder() {
        XCTAssertFalse(
            BindPolicy.shouldWriteTokens(
                importedExpiresAt: Date(timeIntervalSince1970: 50),
                storedExpiresAt: Date(timeIntervalSince1970: 100),
                storedProbeSucceeded: true
            )
        )
    }

    func testWriteTokensWhenImportedExpNewerOrEqual() {
        XCTAssertTrue(
            BindPolicy.shouldWriteTokens(
                importedExpiresAt: Date(timeIntervalSince1970: 100),
                storedExpiresAt: Date(timeIntervalSince1970: 100),
                storedProbeSucceeded: true
            )
        )
        XCTAssertTrue(
            BindPolicy.shouldWriteTokens(
                importedExpiresAt: Date(timeIntervalSince1970: 101),
                storedExpiresAt: Date(timeIntervalSince1970: 100),
                storedProbeSucceeded: true
            )
        )
    }

    private func record(
        seat: SeatID,
        identity: SessionIdentity,
        expiresAt: Date? = Date(timeIntervalSince1970: 100)
    ) throws -> StoredSeatRecord {
        StoredSeatRecord(
            seatID: seat,
            identity: identity,
            access: try XCTUnwrap(AccessToken("access.\(seat.rawValue).sig")),
            refresh: try XCTUnwrap(RefreshToken("refresh.\(seat.rawValue).sig")),
            email: Email("a@example.com"),
            expiresAt: expiresAt,
            membershipType: "pro",
            subscriptionStatus: "active"
        )
    }
}
