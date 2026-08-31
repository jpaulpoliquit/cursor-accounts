import AppKit
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

    func testFallsBackToAccountsTitle() {
        let candidates = [
            DashboardWindowSelection.Candidate(identifier: "x", title: "Prefs", isMiniaturized: false),
            DashboardWindowSelection.Candidate(identifier: nil, title: "Accounts", isMiniaturized: false),
        ]
        XCTAssertEqual(DashboardWindowSelection.index(in: candidates), 1)
    }

    @MainActor
    func testNormalStackingDropsFloatingAndClickThrough() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 180),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.level = .floating
        window.collectionBehavior = .moveToActiveSpace
        window.ignoresMouseEvents = true
        DashboardWindowPresenter.applyNormalWindowStacking(window)
        XCTAssertEqual(window.level, .normal)
        XCTAssertTrue(window.collectionBehavior.contains(.managed))
        XCTAssertFalse(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertEqual(window.alphaValue, 1)
    }

    func testReturnsNilWhenAbsent() {
        let candidates = [
            DashboardWindowSelection.Candidate(identifier: "x", title: "Prefs", isMiniaturized: false),
        ]
        XCTAssertNil(DashboardWindowSelection.index(in: candidates))
    }
}
