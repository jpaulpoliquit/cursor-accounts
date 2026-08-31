import CursorBarDomain
import XCTest

final class OnDemandModeTests: XCTestCase {
    func testPositiveDollarsRejectsNonPositive() {
        XCTAssertNil(PositiveDollars(0))
        XCTAssertNil(PositiveDollars(-1))
        XCTAssertEqual(PositiveDollars(1)?.amount, 1)
        XCTAssertEqual(PositiveDollars(25)?.amount, 25)
    }

    func testFixedFactoryRejectsInvalidAmounts() {
        XCTAssertNil(OnDemandMode.fixed(wholeDollars: 0))
        XCTAssertNil(OnDemandMode.fixed(wholeDollars: -5))
    }

    func testFixedFactoryAcceptsPositiveWholeDollars() {
        guard case let .fixed(dollars)? = OnDemandMode.fixed(wholeDollars: 40) else {
            return XCTFail("expected fixed mode")
        }
        XCTAssertEqual(dollars.amount, 40)
    }

    func testOffAndUnlimitedAreConstructible() {
        let off: OnDemandMode = .off
        let unlimited: OnDemandMode = .unlimited
        XCTAssertEqual(off, .off)
        XCTAssertEqual(unlimited, .unlimited)
    }

    func testHardLimitOffKeyedByNoUsageBasedAllowed() {
        let limit = HardLimit(noUsageBasedAllowed: true, hardLimit: 40)
        XCTAssertEqual(limit, .off)
        XCTAssertEqual(limit?.onDemandMode, .off)
    }

    func testHardLimitUnlimitedAtInt32Max() {
        let limit = HardLimit(noUsageBasedAllowed: false, hardLimit: Int32.max)
        XCTAssertEqual(limit, .unlimited)
        XCTAssertEqual(limit?.onDemandMode, .unlimited)
    }

    func testHardLimitFixedRequiresPositiveWholeDollars() {
        XCTAssertNil(HardLimit(noUsageBasedAllowed: false, hardLimit: 0))
        XCTAssertNil(HardLimit(noUsageBasedAllowed: false, hardLimit: -1))
        guard case let .fixed(dollars)? = HardLimit(noUsageBasedAllowed: false, hardLimit: 2000) else {
            return XCTFail("expected fixed hard limit")
        }
        XCTAssertEqual(dollars.amount, 2000)
        XCTAssertEqual(
            HardLimit(noUsageBasedAllowed: false, hardLimit: 2000)?.onDemandMode,
            OnDemandMode.fixed(wholeDollars: 2000)
        )
    }

    func testHardLimitThrowingInitMatchesFailable() throws {
        let allowed: Bool? = true
        let denied: Bool? = false
        let zero: Int32? = 0
        XCTAssertEqual(try HardLimit(noUsageBasedAllowed: allowed, hardLimit: zero), .off)
        XCTAssertThrowsError(try HardLimit(noUsageBasedAllowed: denied, hardLimit: zero))
        XCTAssertNil(HardLimit(noUsageBasedAllowed: false, hardLimit: 0))
    }
}

