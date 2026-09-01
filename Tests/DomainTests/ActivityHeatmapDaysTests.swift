import CursorBarDomain
import XCTest

final class ActivityHeatmapDaysTests: XCTestCase {
    func testSeriesDailyTokensFillDaysWithoutRequestEvents() {
        let december = UsageDayKey(year: 2025, month: 12, day: 1)
        let june = UsageDayKey(year: 2026, month: 6, day: 10)
        let series = UsageSeries(
            scope: .allAccounts,
            rangeStart: UsageDayKey(year: 2025, month: 10, day: 30),
            rangeEnd: UsageDayKey(year: 2026, month: 8, day: 14),
            points: [
                UsagePoint(day: december, tokens: 40_000_000_000, spendCents: nil, coverage: .complete),
                UsagePoint(day: june, tokens: 12_000, spendCents: nil, coverage: .complete),
                UsagePoint(
                    day: UsageDayKey(year: 2025, month: 11, day: 2),
                    tokens: 0,
                    spendCents: nil,
                    coverage: .complete
                ),
                UsagePoint(
                    day: UsageDayKey(year: 2025, month: 11, day: 3),
                    tokens: 9,
                    spendCents: nil,
                    coverage: .missing
                ),
            ],
            coverage: PartialCoverage(includedAccountCount: 1, requestedAccountCount: 1),
            costAvailable: false
        )

        let days = ActivityHeatmapDays.merge(series: series, insights: nil)
        XCTAssertEqual(days.map(\.day), [
            ActivityDayKey(year: 2025, month: 12, day: 1),
            ActivityDayKey(year: 2026, month: 6, day: 10),
        ])
        XCTAssertEqual(days[0].tokens, 40_000_000_000)
        XCTAssertEqual(days[0].requestCount, 0)
        XCTAssertEqual(days[1].tokens, 12_000)
    }

    func testInsightsRequestCountsMergeOntoSeriesTokens() {
        let key = UsageDayKey(year: 2026, month: 6, day: 10)
        let series = UsageSeries(
            scope: .account(.seat1),
            rangeStart: key,
            rangeEnd: key,
            points: [
                UsagePoint(day: key, tokens: 5_000, spendCents: nil, coverage: .complete),
            ],
            coverage: PartialCoverage(includedAccountCount: 1, requestedAccountCount: 1),
            costAvailable: false
        )
        let insights = stubInsights(
            days: [
                DayActivity(
                    day: ActivityDayKey(year: 2026, month: 6, day: 10),
                    requestCount: 4,
                    tokens: 800,
                    spanMs: 1_000,
                    estimatedActiveMs: 500
                ),
            ]
        )

        let days = ActivityHeatmapDays.merge(series: series, insights: insights)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].tokens, 5_000)
        XCTAssertEqual(days[0].requestCount, 4)
        XCTAssertEqual(days[0].spanMs, 1_000)
    }

    func testInsightsOnlyDayStillAppears() {
        let insights = stubInsights(
            days: [
                DayActivity(
                    day: ActivityDayKey(year: 2026, month: 7, day: 1),
                    requestCount: 2,
                    tokens: 100,
                    spanMs: 0,
                    estimatedActiveMs: 0
                ),
            ]
        )
        let days = ActivityHeatmapDays.merge(series: nil, insights: insights)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].requestCount, 2)
        XCTAssertEqual(days[0].tokens, 100)
    }

    func testEmptyInputsProduceNoDays() {
        XCTAssertTrue(ActivityHeatmapDays.merge(series: nil, insights: nil).isEmpty)
    }

    private func stubInsights(days: [DayActivity]) -> ActivityInsights {
        ActivityInsights(
            scope: .allAccounts,
            range: .month(YearMonth(year: 2026, month: 6)),
            timeZoneIdentifier: "UTC",
            idleGap: .thirtyMinutes,
            hourOfDayCounts: Array(repeating: 0, count: 24),
            dayOfWeekCounts: Array(repeating: 0, count: 7),
            days: days,
            totalRequests: days.reduce(0) { $0 + $1.requestCount },
            totalTokens: days.reduce(0) { $0 + $1.tokens },
            activeDayCount: days.count,
            medianDailySpanMs: nil,
            medianEstimatedActiveMs: nil,
            coverage: ActivityCoverage(
                requestedSeatCount: 1,
                successfulSeatCount: 1,
                truncated: false,
                fetchedEventCount: days.reduce(0) { $0 + $1.requestCount },
                reportedTotalEventCount: nil,
                isPartialMonth: false,
                missingTokenUsageCount: 0
            ),
            monthOverMonth: nil,
            estimatedActiveIsPerSeatSum: false
        )
    }
}
