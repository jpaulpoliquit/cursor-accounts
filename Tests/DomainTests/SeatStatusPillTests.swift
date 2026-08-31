import CursorBarDomain
import XCTest

final class SeatStatusPillTests: XCTestCase {
    func testExhaustedWhenIncludedGoneAndOnDemandOff() {
        let pill = SeatStatusPill.derive(
            .init(included: .exhausted, mode: .off, spend: .idle)
        )
        XCTAssertEqual(pill, .exhausted)
    }

    func testNoPillWhenIncludedRemainingAndOnDemandOff() {
        let pill = SeatStatusPill.derive(
            .init(included: .hasRemaining, mode: .off, spend: .idle)
        )
        XCTAssertNil(pill)
    }

    func testExhaustedWhenExhaustedWithFixedIdle() throws {
        let mode = try XCTUnwrap(OnDemandMode.fixed(wholeDollars: 20))
        let pill = SeatStatusPill.derive(
            .init(included: .exhausted, mode: mode, spend: .idle)
        )
        XCTAssertEqual(pill, .exhausted)
    }

    func testExhaustedWhenExhaustedWithUnlimitedIdle() {
        let pill = SeatStatusPill.derive(
            .init(included: .exhausted, mode: .unlimited, spend: .idle)
        )
        XCTAssertEqual(pill, .exhausted)
    }

    func testOnDemandActiveWhenConsumingFixed() throws {
        let mode = try XCTUnwrap(OnDemandMode.fixed(wholeDollars: 10))
        let pill = SeatStatusPill.derive(
            .init(included: .hasRemaining, mode: mode, spend: .consuming)
        )
        XCTAssertEqual(pill, .onDemandActive)
    }

    func testOnDemandActiveWhenConsumingUnlimitedWhileExhausted() {
        let pill = SeatStatusPill.derive(
            .init(included: .exhausted, mode: .unlimited, spend: .consuming)
        )
        XCTAssertEqual(pill, .onDemandActive)
    }

    func testOnDemandReadyWhenIncludedRemainingAndOnDemandConfiguredButIdle() throws {
        let mode = try XCTUnwrap(OnDemandMode.fixed(wholeDollars: 5))
        let pill = SeatStatusPill.derive(
            .init(included: .hasRemaining, mode: mode, spend: .idle)
        )
        XCTAssertEqual(pill, .onDemandReady)
    }

    func testExhaustedBeatsReadyWhenBothApply() throws {
        let mode = try XCTUnwrap(OnDemandMode.fixed(wholeDollars: 5))
        let pill = SeatStatusPill.derive(
            .init(included: .exhausted, mode: mode, spend: .idle)
        )
        XCTAssertEqual(pill, .exhausted)
    }

    func testIncludedPoolAutoOnly100IsExhausted() {
        let usage = PeriodUsage(
            autoPercentUsed: PercentUsed(unchecked: 100),
            apiPercentUsed: PercentUsed(unchecked: 12),
            totalPercentUsed: PercentUsed(unchecked: 40)
        )
        XCTAssertEqual(SeatStatusPill.includedPool(usage: usage, displayMessage: nil), .exhausted)
        XCTAssertEqual(
            SeatStatusPill.derive(.init(included: .exhausted, mode: .off, spend: .idle)),
            .exhausted
        )
    }

    func testIncludedPoolApiOnly100IsExhausted() {
        let usage = PeriodUsage(
            autoPercentUsed: PercentUsed(unchecked: 68),
            apiPercentUsed: PercentUsed(unchecked: 100),
            totalPercentUsed: PercentUsed(unchecked: 84)
        )
        XCTAssertTrue(usage.isExhausted)
        XCTAssertEqual(SeatStatusPill.includedPool(usage: usage, displayMessage: nil), .exhausted)
    }

    func testIncludedPoolTotalOnly100IsExhausted() {
        let usage = PeriodUsage(
            autoPercentUsed: PercentUsed(unchecked: 40),
            apiPercentUsed: PercentUsed(unchecked: 40),
            totalPercentUsed: PercentUsed(unchecked: 100)
        )
        XCTAssertEqual(SeatStatusPill.includedPool(usage: usage, displayMessage: nil), .exhausted)
    }

    func testOnDemandActiveOutranksExhausted() throws {
        let mode = try XCTUnwrap(OnDemandMode.fixed(wholeDollars: 190))
        let pill = SeatStatusPill.derive(
            .init(included: .exhausted, mode: mode, spend: .consuming)
        )
        XCTAssertEqual(pill, .onDemandActive)
    }

    func testNonExhaustedDisplayMessageOutranksPercent() {
        let usage = PeriodUsage(
            autoPercentUsed: PercentUsed(unchecked: 100),
            apiPercentUsed: PercentUsed(unchecked: 10),
            totalPercentUsed: PercentUsed(unchecked: 50)
        )
        let included = SeatStatusPill.includedPool(
            usage: usage,
            displayMessage: "You still have usage remaining this cycle"
        )
        XCTAssertEqual(included, .hasRemaining)
    }

    func testSecretTokensDoNotPrintRawValues() throws {
        let access = try XCTUnwrap(AccessToken("super-secret-access"))
        let refresh = try XCTUnwrap(RefreshToken("super-secret-refresh"))
        let key = try XCTUnwrap(APIKey("super-secret-key"))
        XCTAssertEqual(String(describing: access), "<AccessToken>")
        XCTAssertEqual(String(reflecting: access), "<AccessToken>")
        XCTAssertEqual(String(describing: refresh), "<RefreshToken>")
        XCTAssertEqual(String(describing: key), "<APIKey>")
        XCTAssertFalse(String(describing: access).contains("super-secret"))
        let credential = Credential.session(
            access: access,
            refresh: refresh,
            expiresAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(String(describing: credential), "<Credential.session>")
        XCTAssertFalse(String(describing: credential).contains("super-secret"))
    }
}
