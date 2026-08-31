import CursorBarDomain
import XCTest

final class UsageRangeTests: XCTestCase {
    func testDefaultIsCurrentMonth() {
        let taipei = TimeZone(identifier: "Asia/Taipei")!
        let now = Date(timeIntervalSince1970: 1_786_320_000) // 2026-08-10 UTC-ish
        let range = UsageRange.defaultMonth(now: now, timeZone: taipei)
        guard case .month(let month) = range else {
            return XCTFail("expected month")
        }
        XCTAssertEqual(month, YearMonth.current(now: now, timeZone: taipei))
    }

    func testPreviousNextAcrossYearAndLeapFebruary() {
        let jan = YearMonth(year: 2024, month: 1)
        XCTAssertEqual(jan.previous, YearMonth(year: 2023, month: 12))
        let feb = YearMonth(year: 2024, month: 2)
        XCTAssertEqual(feb.next, YearMonth(year: 2024, month: 3))
        let leapDayBounds = feb.utcHalfOpenIntervalMs(timeZone: TimeZone(identifier: "Asia/Taipei")!)
        XCTAssertLessThan(leapDayBounds.startMs, leapDayBounds.endExclusiveMs)
        let days = feb.overlappingUTCDays(timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(days.start.day, 1)
        XCTAssertEqual(days.end.day, 29)
    }

    func testNextDisabledOnCurrentMonth() {
        let tz = TimeZone(identifier: "Asia/Taipei")!
        let now = Date(timeIntervalSince1970: 1_786_320_000)
        let current = UsageRange.defaultMonth(now: now, timeZone: tz)
        XCTAssertFalse(current.canGoNext)
        XCTAssertNil(current.next(now: now, timeZone: tz))
        XCTAssertTrue(current.canGoPrevious)
        let previous = try! XCTUnwrap(current.previous())
        XCTAssertTrue(previous.canGoNext)
    }

    func testAsiaTaipeiMonthToUTCHalfOpen() {
        let tz = TimeZone(identifier: "Asia/Taipei")!
        let august = YearMonth(year: 2026, month: 8)
        let bounds = august.utcHalfOpenIntervalMs(timeZone: tz)
        // 2026-08-01 00:00 GMT+8 == 2026-07-31 16:00 UTC
        XCTAssertEqual(bounds.startMs, 1_785_513_600_000)
        // 2026-09-01 00:00 GMT+8 == 2026-08-31 16:00 UTC
        XCTAssertEqual(bounds.endExclusiveMs, 1_788_192_000_000)
        XCTAssertEqual(bounds.endExclusiveMs - bounds.startMs, 31 * 24 * 60 * 60 * 1000)
    }

    func testTodayResetsToCurrentMonth() {
        let tz = TimeZone(identifier: "Asia/Taipei")!
        let now = Date(timeIntervalSince1970: 1_786_320_000)
        var range = UsageRange.month(YearMonth(year: 2026, month: 6))
        range = .defaultMonth(now: now, timeZone: tz)
        XCTAssertEqual(range, .month(YearMonth(year: 2026, month: 8)))
    }

    func testAccessibilityLabels() {
        let month = UsageRange.month(YearMonth(year: 2026, month: 8))
        XCTAssertTrue(month.accessibilityLabel.contains("2026") || month.accessibilityLabel.lowercased().contains("august"))
        XCTAssertNotNil(month.utcEdgeOverlapHint)
        let all = UsageRange.allTime(
            start: UsageDayKey(year: 2025, month: 1, day: 1),
            end: UsageDayKey(year: 2026, month: 8, day: 10)
        )
        XCTAssertTrue(all.accessibilityLabel.lowercased().contains("all time"))
        XCTAssertFalse(all.canGoNext)
        XCTAssertFalse(all.canGoPrevious)
    }

    func testRecentMonthsKeepsNewestAndDropsCreatedAtPad() {
        let tz = TimeZone(secondsFromGMT: 0)!
        let start = UsageDayKey(year: 2025, month: 1, day: 31)
        let end = UsageDayKey(year: 2026, month: 8, day: 15)
        let all = UsageRangeChunks.months(from: start, through: end, timeZone: tz)
        XCTAssertEqual(all.count, 20)
        XCTAssertEqual(all.first, YearMonth(year: 2025, month: 1))
        let recent = UsageRangeChunks.recentMonths(from: start, through: end, timeZone: tz, limit: 6)
        XCTAssertEqual(recent.count, 6)
        XCTAssertEqual(recent.first, YearMonth(year: 2026, month: 3))
        XCTAssertEqual(recent.last, YearMonth(year: 2026, month: 8))
        XCTAssertEqual(
            UsageRangeChunks.recentMonths(from: start, through: end, timeZone: tz, limit: 24).count,
            20
        )
    }

    func testClippedToRecentMonthsKeepsNewestWindow() {
        let tz = TimeZone(secondsFromGMT: 0)!
        let range = UsageRange.allTime(
            start: UsageDayKey(year: 2024, month: 1, day: 15),
            end: UsageDayKey(year: 2026, month: 8, day: 15)
        )
        let clipped = range.clippedToRecentMonths(12, timeZone: tz)
        guard case .allTime(let start, let end) = clipped else {
            return XCTFail("expected allTime")
        }
        XCTAssertEqual(start, UsageDayKey(year: 2025, month: 9, day: 1))
        XCTAssertEqual(end, UsageDayKey(year: 2026, month: 8, day: 15))
        XCTAssertEqual(UsageRange.month(YearMonth(year: 2026, month: 8)).clippedToRecentMonths(12, timeZone: tz), .month(YearMonth(year: 2026, month: 8)))
    }
}
