import CursorBarDomain
import XCTest

final class DashboardTabTests: XCTestCase {
    func testOrderIsAccountsModelsUsage() {
        XCTAssertEqual(DashboardTab.allCases, [.accounts, .models, .usage])
        XCTAssertEqual(DashboardTab.allCases.map(\.title), ["Accounts", "Models", "Usage"])
    }

    func testTitlesAreSpecific() {
        for tab in DashboardTab.allCases {
            XCTAssertFalse(tab.title.isEmpty)
            XCTAssertNotEqual(tab.title, "Home")
        }
    }
}
