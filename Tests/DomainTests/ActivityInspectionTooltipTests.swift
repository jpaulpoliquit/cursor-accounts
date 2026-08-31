import CursorBarDomain
import XCTest

final class ActivityInspectionTooltipTests: XCTestCase {
    func testPeriodTooltipIncludesMethodologyAndSpanCopy() {
        let tz = TimeZone(identifier: "Asia/Taipei")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        var c = DateComponents()
        c.year = 2026
        c.month = 8
        c.day = 10
        c.hour = 9
        let start = Int64(calendar.date(from: c)!.timeIntervalSince1970 * 1000)
        c.hour = 11
        let end = Int64(calendar.date(from: c)!.timeIntervalSince1970 * 1000)
        let inspection = ActivityPeriodInspection(
            label: "Aug 10",
            accessibilityDate: "2026-08-10",
            requestCount: 4,
            tokens: 900,
            firstRequestMs: start,
            lastRequestMs: end,
            spanMs: end - start,
            estimatedActiveMs: 45 * 60_000
        )
        let lines = inspection.tooltipLines(timeZone: tz)
        XCTAssertTrue(lines[0].contains("2026-08-10"))
        XCTAssertTrue(lines.contains(where: { $0.contains("4 requests") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("First ") && $0.contains("→ Last ") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("Daily span") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("Est. active") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("30 minutes") }))
        XCTAssertFalse(lines.joined(separator: " ").lowercased().contains("pauses aren't counted"))
    }
}
