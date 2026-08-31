import CursorBarDomain
import XCTest

final class UsageCachePolicyTests: XCTestCase {
    func testLoginAndManualAlwaysFetch() {
        let now = Date()
        let fresh = now.addingTimeInterval(-10)
        XCTAssertTrue(UsageCachePolicy.needsNetworkFetch(trigger: .signedIn, fetchedAt: fresh, now: now))
        XCTAssertTrue(UsageCachePolicy.needsNetworkFetch(trigger: .manual, fetchedAt: fresh, now: now))
        XCTAssertTrue(UsageCachePolicy.needsNetworkFetch(trigger: .signedIn, fetchedAt: nil, now: now))
    }

    func testOpenAndBootstrapServeFreshCache() {
        let now = Date()
        let fresh = now.addingTimeInterval(-30)
        XCTAssertFalse(UsageCachePolicy.needsNetworkFetch(trigger: .surfaceOpen, fetchedAt: fresh, now: now))
        XCTAssertFalse(UsageCachePolicy.needsNetworkFetch(trigger: .bootstrap, fetchedAt: fresh, now: now))
    }

    func testOpenAndBootstrapFetchWhenMissingOrStale() {
        let now = Date()
        let stale = now.addingTimeInterval(-(UsageCachePolicy.ttl + 1))
        XCTAssertTrue(UsageCachePolicy.needsNetworkFetch(trigger: .surfaceOpen, fetchedAt: nil, now: now))
        XCTAssertTrue(UsageCachePolicy.needsNetworkFetch(trigger: .bootstrap, fetchedAt: stale, now: now))
    }

    func testFiltersOnlyStaleCredentials() {
        let now = Date()
        let seats: [(SeatID, Date?)] = [
            (.seat1, now.addingTimeInterval(-10)),
            (.seat2, nil),
            (.seat3, now.addingTimeInterval(-(UsageCachePolicy.ttl + 5))),
        ]
        let needed = UsageCachePolicy.credentialsNeedingFetch(
            seats,
            seatID: { $0.0 },
            trigger: .surfaceOpen,
            fetchedAt: { id in seats.first(where: { $0.0 == id })?.1 ?? nil },
            now: now
        )
        XCTAssertEqual(needed.map(\.0), [.seat2, .seat3])
    }
}
