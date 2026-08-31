@testable import CursorBar
import XCTest

final class DashboardWindowSelectionTests: XCTestCase {
    func testPrefersStableIdentifierOverTitle() {
        let candidates = [
            DashboardWindowSelection.Candidate(identifier: nil, title: "Dashboard", isMiniaturized: false),
            DashboardWindowSelection.Candidate(
                identifier: DashboardWindowIdentity.itemIdentifier.rawValue,
                title: "Other",
                isMiniaturized: true
            ),
        ]
        XCTAssertEqual(DashboardWindowSelection.index(in: candidates), 1)
    }

    func testFallsBackToDashboardTitle() {
        let candidates = [
            DashboardWindowSelection.Candidate(identifier: "x", title: "Prefs", isMiniaturized: false),
            DashboardWindowSelection.Candidate(identifier: nil, title: "Dashboard", isMiniaturized: false),
        ]
        XCTAssertEqual(DashboardWindowSelection.index(in: candidates), 1)
    }

    func testReturnsNilWhenAbsent() {
        let candidates = [
            DashboardWindowSelection.Candidate(identifier: "x", title: "Prefs", isMiniaturized: false),
        ]
        XCTAssertNil(DashboardWindowSelection.index(in: candidates))
    }
}
