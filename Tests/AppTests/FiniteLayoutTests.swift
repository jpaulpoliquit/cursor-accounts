@testable import CursorBar
import XCTest

final class FiniteLayoutTests: XCTestCase {
    func testRejectsNonFiniteAndNegativeDimensions() {
        XCTAssertNil(FiniteLayout.dimension(CGFloat.nan))
        XCTAssertNil(FiniteLayout.dimension(CGFloat.infinity))
        XCTAssertNil(FiniteLayout.dimension(-1))
        XCTAssertEqual(FiniteLayout.dimension(0), 0)
        XCTAssertEqual(FiniteLayout.dimension(12), 12)
    }

    func testRejectsInvalidRects() {
        XCTAssertNil(FiniteLayout.rect(CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10)))
        let inverted = CGRect(x: 0, y: 0, width: -4, height: 10)
        XCTAssertEqual(inverted.width, 4)
        XCTAssertEqual(inverted.size.width, -4)
        XCTAssertNil(FiniteLayout.rect(inverted))
        XCTAssertNotNil(FiniteLayout.rect(CGRect(x: 1, y: 2, width: 3, height: 4)))
    }
}
