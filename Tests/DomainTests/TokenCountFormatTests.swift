import CursorBarDomain
import XCTest

final class TokenCountFormatTests: XCTestCase {
    func testCompactBoundaryValues() {
        XCTAssertEqual(TokenCountFormat.compact(0), "0")
        XCTAssertEqual(TokenCountFormat.compact(999), "999")
        XCTAssertEqual(TokenCountFormat.compact(1_000), "1K")
        XCTAssertEqual(TokenCountFormat.compact(1_200), "1.2K")
        XCTAssertEqual(TokenCountFormat.compact(1_000_000), "1M")
        XCTAssertEqual(TokenCountFormat.compact(1_200_000), "1.2M")
        XCTAssertEqual(TokenCountFormat.compact(1_000_000_000), "1B")
        XCTAssertEqual(TokenCountFormat.compact(3_000_000_000), "3B")
        XCTAssertEqual(TokenCountFormat.compact(1_200_000_000), "1.2B")
    }

    func testAxisLabelRoundsDoublesWithoutTokenCurrencyMix() {
        XCTAssertEqual(TokenCountFormat.axisLabel(0), "0")
        XCTAssertEqual(TokenCountFormat.axisLabel(999), "999")
        XCTAssertEqual(TokenCountFormat.axisLabel(1_200), "1.2K")
        XCTAssertEqual(TokenCountFormat.axisLabel(1_200_000_000), "1.2B")
    }

    func testAccessibilityKeepsFullLocalizedValue() {
        let full = TokenCountFormat.accessibility(1_200_000)
        XCTAssertFalse(full.contains("M"))
        XCTAssertTrue(full.contains("1") || full.contains("1200000"))
    }

    func testCostAxisNeverUsesTokenSuffixAlone() {
        let label = CostCountFormat.axisLabelCents(120_000, locale: Locale(identifier: "en_US"))
        XCTAssertFalse(label.hasSuffix("K") && !label.contains("$"))
        XCTAssertTrue(label.contains("$") || label.lowercased().contains("usd") || label.contains("1"))
    }
}
