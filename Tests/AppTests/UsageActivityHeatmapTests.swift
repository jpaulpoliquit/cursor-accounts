@testable import CursorBar
import CursorBarDomain
import XCTest

final class UsageActivityHeatmapTests: XCTestCase {
    private let tz = TimeZone(identifier: "America/Los_Angeles")!
    private let now = UsageActivityHeatmapTests.localDate(
        year: 2026,
        month: 8,
        day: 14,
        timeZone: TimeZone(identifier: "America/Los_Angeles")!
    )

    func testMonthRangeUsesOnlyThatMonth() {
        let range = UsageRange.month(YearMonth(year: 2026, month: 2))
        let bounds = UsageActivityHeatmapView.dayBounds(days: [], range: range, timeZone: tz, now: now)
        XCTAssertEqual(bounds?.start, ActivityDayKey(year: 2026, month: 2, day: 1))
        XCTAssertEqual(bounds?.end, ActivityDayKey(year: 2026, month: 2, day: 28))

        let grid = UsageActivityHeatmapView.buildGrid(days: [], range: range, timeZone: tz, now: now)
        XCTAssertFalse(grid.isEmpty)
        XCTAssertTrue(grid.allSatisfy { $0.cells.count == 7 })
        let ids = Set(grid.flatMap(\.cells).map(\.id))
        XCTAssertTrue(ids.contains("2026-02-01"))
        XCTAssertTrue(ids.contains("2026-02-28"))
        XCTAssertFalse(ids.contains("2026-01-01"))
        XCTAssertFalse(ids.contains("2026-08-14"))
        XCTAssertLessThanOrEqual(grid.count, 6)
        XCTAssertEqual(grid.flatMap(\.cells).filter { $0.id.hasPrefix("2026-02-") }.count, 28)
    }

    func testCurrentMonthEndsToday() {
        let range = UsageRange.month(YearMonth(year: 2026, month: 8))
        let bounds = UsageActivityHeatmapView.dayBounds(days: [], range: range, timeZone: tz, now: now)
        XCTAssertEqual(bounds?.start, ActivityDayKey(year: 2026, month: 8, day: 1))
        XCTAssertEqual(bounds?.end, ActivityDayKey(year: 2026, month: 8, day: 14))
        let grid = UsageActivityHeatmapView.buildGrid(days: [], range: range, timeZone: tz, now: now)
        let ids = Set(grid.flatMap(\.cells).map(\.id))
        XCTAssertTrue(ids.contains("2026-08-01"))
        XCTAssertTrue(ids.contains("2026-08-14"))
        XCTAssertLessThanOrEqual(grid.count, 6)
    }

    func testPastMonthDoesNotExpandToYear() {
        let range = UsageRange.month(YearMonth(year: 2025, month: 2))
        let bounds = UsageActivityHeatmapView.dayBounds(days: [], range: range, timeZone: tz, now: now)
        XCTAssertEqual(bounds?.start, ActivityDayKey(year: 2025, month: 2, day: 1))
        XCTAssertEqual(bounds?.end, ActivityDayKey(year: 2025, month: 2, day: 28))

        let grid = UsageActivityHeatmapView.buildGrid(days: [], range: range, timeZone: tz, now: now)
        let ids = Set(grid.flatMap(\.cells).map(\.id))
        XCTAssertTrue(ids.contains("2025-02-01"))
        XCTAssertTrue(ids.contains("2025-02-28"))
        XCTAssertFalse(ids.contains("2025-01-01"))
        XCTAssertFalse(ids.contains("2025-12-31"))
        XCTAssertLessThanOrEqual(grid.count, 6)
    }

    func testActiveDayKeepsItsRequestCount() {
        let range = UsageRange.month(YearMonth(year: 2026, month: 2))
        let day = DayActivity(
            day: ActivityDayKey(year: 2026, month: 2, day: 14),
            requestCount: 9,
            tokens: 100,
            spanMs: 0,
            estimatedActiveMs: 0
        )
        let grid = UsageActivityHeatmapView.buildGrid(days: [day], range: range, timeZone: tz, now: now)
        let cell = grid.flatMap(\.cells).first { $0.id == "2026-02-14" }
        XCTAssertEqual(cell?.requests, 9)
        XCTAssertEqual(grid.flatMap(\.cells).first { $0.id == "2026-02-15" }?.requests, 0)
        XCTAssertNil(grid.flatMap(\.cells).first { $0.id == "2026-01-15" })
    }

    func testAllTimeIgnoresLeadingDaysWithoutRequests() {
        let empty = DayActivity(
            day: ActivityDayKey(year: 2026, month: 2, day: 1),
            requestCount: 0,
            tokens: 0,
            spanMs: 0,
            estimatedActiveMs: 0
        )
        let first = DayActivity(
            day: ActivityDayKey(year: 2026, month: 5, day: 10),
            requestCount: 3,
            tokens: 9,
            spanMs: 0,
            estimatedActiveMs: 0
        )
        let last = DayActivity(
            day: ActivityDayKey(year: 2026, month: 8, day: 14),
            requestCount: 2,
            tokens: 4,
            spanMs: 0,
            estimatedActiveMs: 0
        )
        let range = UsageRange.allTime(
            start: UsageDayKey(year: 2026, month: 2, day: 1),
            end: UsageDayKey(year: 2026, month: 8, day: 14)
        )
        let bounds = UsageActivityHeatmapView.dayBounds(
            days: [empty, first, last],
            range: range,
            timeZone: tz,
            now: now
        )
        XCTAssertEqual(bounds?.start, first.day)
        XCTAssertEqual(bounds?.end, last.day)
        let grid = UsageActivityHeatmapView.buildGrid(
            days: [empty, first, last],
            range: range,
            timeZone: tz,
            now: now
        )
        let ids = Set(grid.flatMap(\.cells).map(\.id))
        XCTAssertTrue(ids.contains("2026-05-10"))
        XCTAssertTrue(ids.contains("2026-08-14"))
        XCTAssertFalse(ids.contains("2026-02-01"))
    }

    func testAllTimeSpansFirstToLastActiveDay() {
        let start = ActivityDayKey(year: 2026, month: 1, day: 10)
        let end = ActivityDayKey(year: 2026, month: 1, day: 20)
        let days = [
            DayActivity(day: start, requestCount: 1, tokens: 1, spanMs: 0, estimatedActiveMs: 0),
            DayActivity(day: end, requestCount: 2, tokens: 2, spanMs: 0, estimatedActiveMs: 0),
        ]
        let range = UsageRange.allTime(
            start: UsageDayKey(year: 2026, month: 1, day: 1),
            end: UsageDayKey(year: 2026, month: 1, day: 31)
        )
        let bounds = UsageActivityHeatmapView.dayBounds(days: days, range: range, timeZone: tz, now: now)
        XCTAssertEqual(bounds?.start, start)
        XCTAssertEqual(bounds?.end, end)
        let grid = UsageActivityHeatmapView.buildGrid(days: days, range: range, timeZone: tz, now: now)
        let ids = Set(grid.flatMap(\.cells).map(\.id))
        XCTAssertTrue(ids.contains("2026-01-10"))
        XCTAssertTrue(ids.contains("2026-01-20"))
        XCTAssertFalse(ids.contains("2026-08-14"))
    }

    func testAllTimeUnderEightyWeeksKeepsFullSpan() {
        let start = ActivityDayKey(year: 2025, month: 1, day: 1)
        let end = ActivityDayKey(year: 2026, month: 2, day: 20)
        let days = [
            DayActivity(day: start, requestCount: 1, tokens: 1, spanMs: 0, estimatedActiveMs: 0),
            DayActivity(day: end, requestCount: 2, tokens: 2, spanMs: 0, estimatedActiveMs: 0),
        ]
        let range = UsageRange.allTime(
            start: UsageDayKey(year: 2025, month: 1, day: 1),
            end: UsageDayKey(year: 2026, month: 2, day: 20)
        )
        let grid = UsageActivityHeatmapView.buildGrid(days: days, range: range, timeZone: tz, now: now)
        let ids = Set(grid.flatMap(\.cells).map(\.id))
        XCTAssertGreaterThan(grid.count, 56)
        XCTAssertLessThanOrEqual(grid.count, 80)
        XCTAssertTrue(ids.contains("2025-01-01"))
        XCTAssertTrue(ids.contains("2026-02-20"))
    }

    func testMonthLabelsUseNarrowInitialsLikeCursorProfile() {
        let days = [
            DayActivity(
                day: ActivityDayKey(year: 2026, month: 1, day: 10),
                requestCount: 1,
                tokens: 1,
                spanMs: 0,
                estimatedActiveMs: 0
            ),
            DayActivity(
                day: ActivityDayKey(year: 2026, month: 6, day: 10),
                requestCount: 1,
                tokens: 1,
                spanMs: 0,
                estimatedActiveMs: 0
            ),
            DayActivity(
                day: ActivityDayKey(year: 2026, month: 7, day: 10),
                requestCount: 2,
                tokens: 2,
                spanMs: 0,
                estimatedActiveMs: 0
            ),
        ]
        let range = UsageRange.allTime(
            start: UsageDayKey(year: 2026, month: 1, day: 1),
            end: UsageDayKey(year: 2026, month: 7, day: 31)
        )
        let grid = UsageActivityHeatmapView.buildGrid(days: days, range: range, timeZone: tz, now: now)
        let labels = grid.map(\.monthLabel).filter { !$0.isEmpty }
        XCTAssertTrue(labels.allSatisfy { $0.count == 1 })
        XCTAssertTrue(labels.contains("J"))
        XCTAssertGreaterThanOrEqual(labels.filter { $0 == "J" }.count, 2)
    }

    func testLayoutHitTestUsesCellRectsNotStrideGaps() {
        let day = DayActivity(
            day: ActivityDayKey(year: 2026, month: 2, day: 2),
            requestCount: 4,
            tokens: 8,
            spanMs: 0,
            estimatedActiveMs: 0
        )
        let range = UsageRange.month(YearMonth(year: 2026, month: 2))
        let layout = HeatmapLayout.make(
            days: [day],
            range: range,
            timeZone: tz,
            cell: 10,
            gap: 2,
            now: now
        )
        XCTAssertFalse(layout.grid.isEmpty)
        let origin = layout.cellOrigin(week: 0, row: 0)
        let inside = CGPoint(x: origin.x + 5, y: origin.y + 5)
        XCTAssertNotNil(layout.cell(at: inside))
        let inGap = CGPoint(x: origin.x + 11, y: origin.y + 5)
        XCTAssertNil(layout.cell(at: inGap))
        XCTAssertNil(layout.cell(at: CGPoint(x: 5, y: 4)))
        if let id = layout.cell(at: inside)?.id {
            XCTAssertEqual(layout.frame(of: id)?.origin, origin)
        }
    }

    func testWeekdayAbbreviationsAreMondayFirst() {
        let labels = UsageActivityHeatmapView.weekdayAbbreviations(
            timeZone: tz,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(labels, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(UsageActivityHeatmapView.weekdayGutterLabels(), ["M", "", "W", "", "F", "", ""])
    }

    func testAllTimeLongerThanEightyWeeksIsCapped() {
        let start = ActivityDayKey(year: 2024, month: 1, day: 10)
        let end = ActivityDayKey(year: 2026, month: 8, day: 14)
        let days = [
            DayActivity(day: start, requestCount: 1, tokens: 1, spanMs: 0, estimatedActiveMs: 0),
            DayActivity(day: end, requestCount: 2, tokens: 2, spanMs: 0, estimatedActiveMs: 0),
        ]
        let range = UsageRange.allTime(
            start: UsageDayKey(year: 2024, month: 1, day: 10),
            end: UsageDayKey(year: 2026, month: 8, day: 14)
        )
        let grid = UsageActivityHeatmapView.buildGrid(days: days, range: range, timeZone: tz, now: now)
        XCTAssertEqual(grid.count, 80)
        XCTAssertTrue(grid.flatMap(\.cells).contains { $0.id == "2024-01-10" })
    }

    private static func localDate(year: Int, month: Int, day: Int, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
