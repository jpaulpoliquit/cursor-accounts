import CursorBarDomain
import XCTest

final class OpenRefreshGateTests: XCTestCase {
    func testMenuOpenRefreshesCardsOnly() {
        let decision = OpenRefreshGate.mergedDecision(surfaces: [.menuBar])
        XCTAssertTrue(decision.shouldRefreshCards)
        XCTAssertFalse(decision.shouldRefreshSeries)
    }

    func testDashboardOpenRefreshesCardsAndSeries() {
        let decision = OpenRefreshGate.mergedDecision(surfaces: [.dashboard])
        XCTAssertTrue(decision.shouldRefreshCards)
        XCTAssertTrue(decision.shouldRefreshSeries)
    }

    func testDebouncedMergeIncludesDashboardSeries() {
        let decision = OpenRefreshGate.mergedDecision(surfaces: [.menuBar, .dashboard])
        XCTAssertTrue(decision.shouldRefreshCards)
        XCTAssertTrue(decision.shouldRefreshSeries)
    }
}
