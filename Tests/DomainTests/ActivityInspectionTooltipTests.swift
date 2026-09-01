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
        XCTAssertFalse(lines.contains(where: { $0.contains("Daily span") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("Est. active") }))
        XCTAssertFalse(lines.contains(where: { $0.contains("30 minutes") }))
        XCTAssertFalse(lines.joined(separator: " ").lowercased().contains("pauses aren't counted"))
    }

    func testMonthBucketTooltipOmitsDailySpanAndClockRange() {
        let tz = TimeZone(identifier: "Asia/Taipei")!
        let inspection = ActivityPeriodInspection(
            label: "August 2026",
            accessibilityDate: "August 2026",
            requestCount: 28_616,
            tokens: 17_600_000_000,
            firstRequestMs: 1,
            lastRequestMs: 2,
            spanMs: 3_512_000_000,
            estimatedActiveMs: 1_651_200_000,
            isMonthBucket: true
        )
        let lines = inspection.tooltipLines(timeZone: tz)
        XCTAssertEqual(lines[0], "August 2026")
        XCTAssertTrue(lines.contains(where: { $0.contains("\(TokenCountFormat.grouped(28_616)) requests") }))
        XCTAssertFalse(lines.contains(where: { $0.contains("First ") }))
        XCTAssertFalse(lines.contains(where: { $0.contains("Daily span") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("Est. active") }))
    }
}
