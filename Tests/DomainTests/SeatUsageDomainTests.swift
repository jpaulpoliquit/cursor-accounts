import CursorBarDomain
import XCTest

final class SeatUsageDomainTests: XCTestCase {
    func testPercentUsedRejectsNonFinite() {
        XCTAssertNil(PercentUsed(percent: .nan))
        XCTAssertNil(PercentUsed(percent: .infinity))
        XCTAssertEqual(PercentUsed(percent: 100)?.percent, 100)
        XCTAssertEqual(PercentUsed(percent: 142.5)?.percent, 142.5)
    }

    func testHardLimitSetWireBodies() {
        XCTAssertEqual(HardLimit.off.setHardLimitWire.hardLimit, 0)
        XCTAssertEqual(HardLimit.off.setHardLimitWire.noUsageBasedAllowed, true)
        XCTAssertEqual(HardLimit.unlimited.setHardLimitWire.hardLimit, Int32.max)
        XCTAssertEqual(HardLimit.unlimited.setHardLimitWire.noUsageBasedAllowed, false)
        let fixed = HardLimit.fixed(PositiveDollars(40)!)
        XCTAssertEqual(fixed.setHardLimitWire.hardLimit, 40)
        XCTAssertEqual(fixed.setHardLimitWire.noUsageBasedAllowed, false)
    }

    func testStatusPillExhaustedFromDisplayMessage() {
        let usage = PeriodUsage(
            autoPercentUsed: PercentUsed(unchecked: 10),
            apiPercentUsed: PercentUsed(unchecked: 10),
            totalPercentUsed: PercentUsed(unchecked: 10)
        )
        let included = SeatStatusPill.includedPool(
            usage: usage,
            displayMessage: "You've used all of your included usage"
        )
        XCTAssertEqual(included, .exhausted)
        let pill = SeatStatusPill.derive(
            .init(included: included, mode: .off, spend: .idle)
        )
        XCTAssertEqual(pill, .exhausted)
    }

    func testPeriodUsageExhaustedFromAnyPool() {
        let apiOnly = PeriodUsage(
            autoPercentUsed: PercentUsed(unchecked: 10),
            apiPercentUsed: PercentUsed(unchecked: 100),
            totalPercentUsed: PercentUsed(unchecked: 55)
        )
        XCTAssertTrue(apiOnly.isExhausted)
        let autoOnly = PeriodUsage(
            autoPercentUsed: PercentUsed(unchecked: 100),
            apiPercentUsed: PercentUsed(unchecked: 10),
            totalPercentUsed: PercentUsed(unchecked: 55)
        )
        XCTAssertTrue(autoOnly.isExhausted)
        let totalOnly = PeriodUsage(
            autoPercentUsed: PercentUsed(unchecked: 10),
            apiPercentUsed: PercentUsed(unchecked: 10),
            totalPercentUsed: PercentUsed(unchecked: 100)
        )
        XCTAssertTrue(totalOnly.isExhausted)
        let under = PeriodUsage(
            autoPercentUsed: PercentUsed(unchecked: 99),
            apiPercentUsed: PercentUsed(unchecked: 99),
            totalPercentUsed: PercentUsed(unchecked: 99)
        )
        XCTAssertFalse(under.isExhausted)
    }

    func testOnDemandActiveRequiresProvenUsage() {
        let mode = OnDemandMode.fixed(wholeDollars: 20)!
        let consuming = OnDemandState(
            mode: mode,
            individualUsed: AmountCents(cents: 12)
        )
        XCTAssertTrue(consuming.isConsuming)
        let idle = OnDemandState(mode: mode, individualUsed: AmountCents(cents: 0))
        XCTAssertFalse(idle.isConsuming)
        XCTAssertFalse(OnDemandState(mode: .off, individualUsed: AmountCents(cents: 99)).isConsuming)

        let active = SeatStatusPill.derive(
            .init(included: .hasRemaining, mode: mode, spend: .consuming)
        )
        XCTAssertEqual(active, .onDemandActive)
        let exhausted = SeatStatusPill.derive(
            .init(included: .exhausted, mode: mode, spend: .idle)
        )
        XCTAssertEqual(exhausted, .exhausted)
        let ready = SeatStatusPill.derive(
            .init(included: .hasRemaining, mode: mode, spend: .idle)
        )
        XCTAssertEqual(ready, .onDemandReady)
    }

    func testSeatUsageSnapshotHasNoCredentialFieldsAndDerivesPill() throws {
        let snapshot = SeatUsageSnapshot(
            seatID: .seat1,
            plan: PlanInfo(name: "ultra", includedAmountCents: AmountCents(cents: 20_000)),
            period: PeriodUsageDetail(
                usage: PeriodUsage(
                    autoPercentUsed: PercentUsed(unchecked: 100),
                    apiPercentUsed: PercentUsed(unchecked: 100),
                    totalPercentUsed: PercentUsed(unchecked: 100)
                ),
                displayMessage: nil,
                spendLimitUsage: SpendLimitUsage(individualUsed: AmountCents(cents: 0))
            ),
            hardLimit: .fixed(PositiveDollars(40)!),
            credits: .absent,
            policy: UsagePolicy(canAdjustOnDemand: true),
            fetchedAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertEqual(snapshot.statusPill, .exhausted)
        let data = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("accessToken"))
        XCTAssertFalse(json.contains("refreshToken"))
        XCTAssertFalse(json.contains("Bearer"))
        XCTAssertFalse(json.contains("crsr_"))
    }

    func testWrittenUnconfirmedIsDistinctFromFailureAndSuccess() {
        let phase = SetHardLimitPhase.writtenUnconfirmed(.seat2)
        if case .failed = phase {
            XCTFail("writtenUnconfirmed must not collapse to failed")
        }
        if case .succeeded = phase {
            XCTFail("writtenUnconfirmed must not collapse to succeeded")
        }
        XCTAssertEqual(phase, .writtenUnconfirmed(.seat2))
        XCTAssertEqual(
            SetHardLimitSuccess.writtenUnconfirmed(.seat3),
            .writtenUnconfirmed(.seat3)
        )
    }
}
