import CursorBarDomain
import XCTest

final class UsageWorkPolicyTests: XCTestCase {
    private let now = Date()

    func testDashboardWinsSurfaceMerge() {
        XCTAssertEqual(UsageWorkPolicy.surface(from: [.menuBar, .dashboard]), .dashboard)
        XCTAssertEqual(UsageWorkPolicy.surface(from: [.menuBar]), .menuBar)
        XCTAssertEqual(UsageWorkPolicy.surface(from: []), .hidden)
    }

    func testHiddenCancelsWarmAndSkipsSeries() {
        XCTAssertEqual(
            decision(surface: .hidden, work: .historyWarm, trigger: .bootstrap, hasLastKnown: true),
            .cancel
        )
        XCTAssertEqual(
            decision(surface: .hidden, work: .seriesRefresh, trigger: .bootstrap, hasLastKnown: true),
            .skip
        )
    }

    func testHiddenBootstrapSkipsCardsWhenLastKnownExists() {
        let stale = now.addingTimeInterval(-(UsageCachePolicy.ttl + 1))
        XCTAssertEqual(
            decision(
                surface: .hidden,
                work: .cardRefresh,
                trigger: .bootstrap,
                hasLastKnown: true,
                fetchedAt: stale
            ),
            .skip
        )
        XCTAssertEqual(
            decision(
                surface: .hidden,
                work: .cardRefresh,
                trigger: .bootstrap,
                hasLastKnown: true,
                fetchedAt: now
            ),
            .skip
        )
        XCTAssertEqual(
            decision(surface: .hidden, work: .cardRefresh, trigger: .bootstrap, hasLastKnown: false),
            .fetchNow
        )
    }

    func testMenuOpenRefreshesStaleCardsOnly() {
        let stale = now.addingTimeInterval(-(UsageCachePolicy.ttl + 1))
        XCTAssertEqual(
            decision(
                surface: .menuBar,
                work: .cardRefresh,
                trigger: .surfaceOpen,
                hasLastKnown: true,
                fetchedAt: stale
            ),
            .showThenFetch
        )
        XCTAssertEqual(
            decision(surface: .menuBar, work: .seriesRefresh, trigger: .surfaceOpen, hasLastKnown: true),
            .skip
        )
        XCTAssertEqual(
            decision(surface: .menuBar, work: .historyWarm, trigger: .surfaceOpen, hasLastKnown: true),
            .skip
        )
    }

    func testDashboardAllowsWarmAndSeriesSWR() {
        let stale = now.addingTimeInterval(-(UsageCachePolicy.ttl + 1))
        XCTAssertEqual(
            decision(surface: .dashboard, work: .historyWarm, trigger: .surfaceOpen, hasLastKnown: true),
            .opportunistic
        )
        XCTAssertEqual(
            decision(
                surface: .dashboard,
                work: .seriesRefresh,
                trigger: .surfaceOpen,
                hasLastKnown: true,
                fetchedAt: stale
            ),
            .showThenFetch
        )
        XCTAssertEqual(
            decision(
                surface: .dashboard,
                work: .seriesRefresh,
                trigger: .surfaceOpen,
                hasLastKnown: true,
                fetchedAt: now
            ),
            .skip
        )
    }

    func testManualKeepsLastKnownVisible() {
        XCTAssertEqual(
            decision(surface: .menuBar, work: .cardRefresh, trigger: .manual, hasLastKnown: true),
            .showThenFetch
        )
        XCTAssertEqual(
            decision(surface: .menuBar, work: .cardRefresh, trigger: .manual, hasLastKnown: false),
            .fetchNow
        )
    }

    func testRawEventsStayOnlyWhileDashboardIsOpen() {
        XCTAssertTrue(UsageWorkPolicy.retainsRawEventMonths(.dashboard))
        XCTAssertFalse(UsageWorkPolicy.retainsRawEventMonths(.hidden))
        XCTAssertFalse(UsageWorkPolicy.retainsRawEventMonths(.menuBar))
    }

    func testLoadStateStaysReadyWhileRefreshingWhenSnapshotExists() {
        let state = SeatUsageLoadState.resolve(
            auth: .signedIn,
            hasSnapshot: true,
            refreshPhase: .refreshing(.all),
            seatID: .seat1
        )
        XCTAssertEqual(state, .ready)
    }

    private func decision(
        surface: UsageSurface,
        work: UsageWorkKind,
        trigger: UsageFetchTrigger,
        hasLastKnown: Bool,
        fetchedAt: Date? = nil
    ) -> UsageWorkDecision {
        UsageWorkPolicy.decision(
            surface: surface,
            work: work,
            trigger: trigger,
            hasLastKnown: hasLastKnown,
            fetchedAt: fetchedAt ?? (hasLastKnown ? now : nil),
            now: now
        )
    }
}
