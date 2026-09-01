import CursorBarDomain
import XCTest

final class ActivityAnalyzerTests: XCTestCase {
    private var taipei: TimeZone { TimeZone(identifier: "Asia/Taipei")! }

    func testSingletonDayHasZeroSpanAndZeroEstimatedActive() {
        let requests = [req(ms: dayMs(2026, 8, 10, 10, 0))]
        let days = ActivityAnalyzer.dayMetrics(requests, timeZone: taipei, idleGap: .thirtyMinutes)
        XCTAssertEqual(days.count, 1)
        let day = days.values.first!
        XCTAssertEqual(day.requestCount, 1)
        XCTAssertEqual(day.spanMs, 0)
        XCTAssertEqual(day.estimatedActiveMs, 0)
    }

    func testDenseDayEstimatedActiveEqualsSpanForSubGapDeltas() {
        let start = dayMs(2026, 8, 10, 9, 0)
        let requests = (0..<6).map { req(ms: start + Int64($0) * 5 * 60_000) }
        let days = ActivityAnalyzer.dayMetrics(requests, timeZone: taipei, idleGap: .thirtyMinutes)
        let day = days.values.first!
        XCTAssertEqual(day.spanMs, 25 * 60_000)
        XCTAssertEqual(day.estimatedActiveMs, day.spanMs)
    }

    func testLongIdleGapIsCappedAtThirtyMinutes() {
        let start = dayMs(2026, 8, 10, 9, 0)
        let requests = [
            req(ms: start),
            req(ms: start + 10 * 60_000),
            req(ms: start + 3 * 60 * 60_000),
        ]
        let days = ActivityAnalyzer.dayMetrics(requests, timeZone: taipei, idleGap: .thirtyMinutes)
        let day = days.values.first!
        XCTAssertEqual(day.spanMs, 3 * 60 * 60_000)
        XCTAssertEqual(day.estimatedActiveMs, 10 * 60_000 + 30 * 60_000)
    }

    func testHourAndWeekdayBucketInInjectedTimeZone() {
        let ms = dayMs(2026, 8, 10, 9, 30)
        let insights = ActivityAnalyzer.analyze(
            seats: [.init(seatID: .seat1, requests: [req(ms: ms)], truncated: false, reportedTotal: 1)],
            scope: .account(.seat1),
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: taipei,
            now: Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0),
            requestedSeatCount: 1
        )
        XCTAssertEqual(insights.hourOfDayCounts[9], 1)
        XCTAssertEqual(insights.totalRequests, 1)
        // 2026-08-10 is Monday → index 0
        XCTAssertEqual(insights.dayOfWeekCounts[0], 1)
    }

    func testAllAccountsSumsPerSeatEstimatedActiveWithoutMergingSessions() {
        let dayStart = dayMs(2026, 8, 10, 9, 0)
        let seat1 = [
            req(ms: dayStart),
            req(ms: dayStart + 20 * 60_000),
        ]
        // Seat 2 overlaps the same wall clock window.
        let seat2 = [
            req(ms: dayStart + 5 * 60_000),
            req(ms: dayStart + 25 * 60_000),
        ]
        let insights = ActivityAnalyzer.analyze(
            seats: [
                .init(seatID: .seat1, requests: seat1, truncated: false, reportedTotal: 2),
                .init(seatID: .seat2, requests: seat2, truncated: false, reportedTotal: 2),
            ],
            scope: .allAccounts,
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: taipei,
            now: Date(timeIntervalSince1970: TimeInterval(dayStart) / 1000.0 + 86400),
            requestedSeatCount: 2
        )
        XCTAssertTrue(insights.estimatedActiveIsPerSeatSum)
        XCTAssertEqual(insights.spanLabel, "Combined span")
        XCTAssertTrue(insights.spanHelp.contains("exceed 24 hours"))
        XCTAssertEqual(insights.agentTimeLabel, "Agent time")
        XCTAssertTrue(insights.agentTimeHelp.contains("Summed per account"))
        XCTAssertEqual(insights.totalRequests, 4)
        XCTAssertEqual(insights.activeDayCount, 1)
        let day = insights.days[0]
        // Each seat span 20m; summed span 40m. Calendar first-to-last is 25m.
        XCTAssertEqual(day.spanMs, 40 * 60_000)
        XCTAssertEqual(day.calendarSpanMs, 25 * 60_000)
        XCTAssertEqual(day.estimatedActiveMs, 40 * 60_000)
        XCTAssertEqual(
            insights.trailingSpanMs(
                now: Date(timeIntervalSince1970: TimeInterval(dayStart) / 1000.0 + 86400),
                timeZone: taipei
            ),
            25 * 60_000
        )
    }

    func testMonthOverMonthProseSuppressedForPartialCurrentMonth() throws {
        let now = date(2026, 8, 10, 12, 0)
        let current = (0..<60).map { req(ms: dayMs(2026, 8, 1 + ($0 % 10), 10, $0 % 50)) }
        let previous = (0..<60).map { req(ms: dayMs(2026, 7, 1 + ($0 % 10), 10, $0 % 50)) }
        let insights = ActivityAnalyzer.analyze(
            seats: [.init(seatID: .seat1, requests: current, truncated: false, reportedTotal: 60)],
            scope: .account(.seat1),
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: taipei,
            now: now,
            previousMonthSeats: [.init(seatID: .seat1, requests: previous, truncated: false, reportedTotal: 60)],
            requestedSeatCount: 1
        )
        let mom = try XCTUnwrap(insights.monthOverMonth)
        XCTAssertTrue(mom.currentIsPartial)
        XCTAssertTrue(mom.currentLabel.contains("so far"))
        XCTAssertTrue(mom.versusLabel.hasPrefix("vs "))
        XCTAssertFalse(mom.versusLabel.contains("so far"))
        XCTAssertFalse(mom.allowsProse)
        XCTAssertTrue(mom.proseLines.isEmpty)
    }

    func testMonthOverMonthProseRequiresSampleThresholds() throws {
        let now = date(2026, 8, 31, 12, 0)
        let current = [req(ms: dayMs(2026, 8, 10, 10, 0))]
        let previous = [req(ms: dayMs(2026, 7, 10, 10, 0))]
        let insights = ActivityAnalyzer.analyze(
            seats: [.init(seatID: .seat1, requests: current, truncated: false, reportedTotal: 1)],
            scope: .account(.seat1),
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: taipei,
            now: now,
            previousMonthSeats: [.init(seatID: .seat1, requests: previous, truncated: false, reportedTotal: 1)],
            requestedSeatCount: 1
        )
        let mom = try XCTUnwrap(insights.monthOverMonth)
        XCTAssertFalse(mom.allowsProse)
    }

    func testAccessibilityNeverSaysUnqualifiedAgentHours() {
        let insights = ActivityAnalyzer.analyze(
            seats: [
                .init(
                    seatID: .seat1,
                    requests: [req(ms: dayMs(2026, 8, 10, 10, 0)), req(ms: dayMs(2026, 8, 10, 11, 0))],
                    truncated: false,
                    reportedTotal: 2
                ),
            ],
            scope: .account(.seat1),
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: taipei,
            now: date(2026, 8, 31, 12, 0),
            requestedSeatCount: 1
        )
        XCTAssertFalse(insights.estimatedActiveIsPerSeatSum)
        XCTAssertEqual(insights.spanLabel, "Daily span")
        let text = insights.accessibilityDescriptor.lowercased()
        XCTAssertFalse(text.contains("agent hours"))
        XCTAssertTrue(text.contains("estimated agent-active"))
        XCTAssertTrue(text.contains("daily span") || text.contains("span"))
    }

    func testBillingKindUnknownIsExhaustiveSafe() {
        XCTAssertEqual(BillingKind(wireName: "USAGE_EVENT_KIND_INCLUDED_IN_ULTRA"), .includedInUltra)
        if case .unknown(let raw) = BillingKind(wireName: "FUTURE_KIND") {
            XCTAssertEqual(raw, "FUTURE_KIND")
        } else {
            XCTFail("expected unknown")
        }
    }

    func testMonthOverMonthProseSuppressedWhenPreviousPeriodPartialSeatCoverage() throws {
        let now = date(2026, 8, 31, 12, 0)
        let current = (0..<60).map { req(ms: dayMs(2026, 8, 1 + ($0 % 10), 10, $0 % 50)) }
        let previous = (0..<60).map { req(ms: dayMs(2026, 7, 1 + ($0 % 10), 10, $0 % 50)) }
        let insights = ActivityAnalyzer.analyze(
            seats: [
                .init(seatID: .seat1, requests: current, truncated: false, reportedTotal: 60),
                .init(seatID: .seat2, requests: current, truncated: false, reportedTotal: 60),
            ],
            scope: .allAccounts,
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: taipei,
            now: now,
            previousMonthSeats: [
                .init(seatID: .seat1, requests: previous, truncated: false, reportedTotal: 60),
            ],
            requestedSeatCount: 2,
            previousRequestedSeatCount: 2
        )
        let mom = try XCTUnwrap(insights.monthOverMonth)
        XCTAssertFalse(mom.allowsProse)
        XCTAssertTrue(mom.proseLines.isEmpty)
    }

    func testIdleGapCopyStatesThirtyMinuteCap() {
        let copy = IdleGapPolicy.thirtyMinutes.methodologyCopy
        XCTAssertTrue(copy.contains("30 minutes"))
        XCTAssertTrue(copy.contains("Each gap between requests is capped at"))
        XCTAssertFalse(copy.lowercased().contains("pauses aren't counted"))
        XCTAssertFalse(copy.lowercased().contains("pauses are not counted"))
        let a11y = IdleGapPolicy.thirtyMinutes.accessibilityLabel
        XCTAssertTrue(a11y.contains("30 minutes"))
        XCTAssertTrue(a11y.contains("Each gap between requests is capped at"))
    }

    func testAllAccountsAllTimeFirstDayIsEarliestRequestAmongSeats() {
        let march = dayMs(2026, 3, 1, 10, 0)
        let june = dayMs(2026, 6, 1, 11, 0)
        let insights = ActivityAnalyzer.analyze(
            seats: [
                .init(
                    seatID: .seat1,
                    requests: [req(ms: june)],
                    truncated: false,
                    reportedTotal: 1
                ),
                .init(
                    seatID: .seat2,
                    requests: [req(ms: march), req(ms: june)],
                    truncated: false,
                    reportedTotal: 2
                ),
            ],
            scope: .allAccounts,
            range: .allTime(
                start: UsageDayKey(year: 2026, month: 2, day: 1),
                end: UsageDayKey(year: 2026, month: 8, day: 14)
            ),
            timeZone: taipei,
            now: date(2026, 8, 14, 12, 0),
            requestedSeatCount: 2
        )
        XCTAssertEqual(insights.totalRequests, 3)
        XCTAssertEqual(insights.days.first?.day, ActivityDayKey.localDay(timestampMs: march, timeZone: taipei))
        XCTAssertEqual(insights.days.count, 2)
        let first = insights.days[0]
        XCTAssertEqual(first.requestCount, 1)
        XCTAssertEqual(first.contributions.map(\.seatID), [.seat2])
        let later = insights.days[1]
        XCTAssertEqual(Set(later.contributions.map(\.seatID)), [.seat1, .seat2])
        XCTAssertEqual(later.requestCount, 2)
    }

    func testCoverageCaptionIncludesTruncation() throws {
        let coverage = ActivityCoverage(
            requestedSeatCount: 2,
            successfulSeatCount: 1,
            truncated: true,
            fetchedEventCount: 500,
            reportedTotalEventCount: 2000,
            isPartialMonth: true,
            missingTokenUsageCount: 0
        )
        let caption = try XCTUnwrap(coverage.caption)
        XCTAssertTrue(caption.contains("\(TokenCountFormat.grouped(500)) of \(TokenCountFormat.grouped(2000)) requests"))
        XCTAssertTrue(caption.contains("Month so far"))
        XCTAssertTrue(caption.contains("1 of 2"))
        XCTAssertTrue(caption.contains("1 account unavailable"))
        XCTAssertFalse(caption.contains("try Refresh"))
        XCTAssertFalse(caption.contains("history still loading"))
    }

    func testCoverageCaptionDistinguishesFailedSeats() throws {
        let coverage = ActivityCoverage(
            requestedSeatCount: 5,
            successfulSeatCount: 4,
            truncated: false,
            fetchedEventCount: 100,
            reportedTotalEventCount: nil,
            isPartialMonth: false,
            missingTokenUsageCount: 0
        )
        let caption = try XCTUnwrap(coverage.caption)
        XCTAssertEqual(caption, "4 of 5 accounts · 1 account unavailable")
    }

    func testTrailingThirtyDaysSumsOnlyRecentAgentTime() {
        let old = DayActivity(
            day: ActivityDayKey(year: 2026, month: 6, day: 1),
            requestCount: 2,
            tokens: 10,
            spanMs: 3_600_000,
            estimatedActiveMs: 3_600_000
        )
        let recent = DayActivity(
            day: ActivityDayKey(year: 2026, month: 8, day: 20),
            requestCount: 4,
            tokens: 20,
            spanMs: 2 * 3_600_000,
            estimatedActiveMs: 90 * 60_000
        )
        let insights = ActivityAnalyzer.analyze(
            seats: [.init(seatID: .seat1, requests: [], truncated: false, reportedTotal: 0)],
            scope: .account(.seat1),
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: taipei,
            now: date(2026, 8, 31, 12, 0),
            requestedSeatCount: 1
        )
        let withDays = ActivityInsights(
            scope: insights.scope,
            range: insights.range,
            timeZoneIdentifier: insights.timeZoneIdentifier,
            idleGap: insights.idleGap,
            hourOfDayCounts: insights.hourOfDayCounts,
            hourOfDayTokens: insights.hourOfDayTokens,
            dayOfWeekCounts: insights.dayOfWeekCounts,
            days: [old, recent],
            totalRequests: 6,
            totalTokens: 30,
            activeDayCount: 2,
            medianDailySpanMs: insights.medianDailySpanMs,
            medianEstimatedActiveMs: insights.medianEstimatedActiveMs,
            coverage: insights.coverage,
            monthOverMonth: nil,
            estimatedActiveIsPerSeatSum: false
        )
        let now = date(2026, 8, 31, 12, 0)
        XCTAssertEqual(withDays.trailingDays(dayCount: 30, now: now, timeZone: taipei).map(\.day), [recent.day])
        XCTAssertEqual(withDays.totalAgentTimeMs, 3_600_000 + (90 * 60_000))
        XCTAssertEqual(withDays.trailingAgentTimeMs(now: now, timeZone: taipei), 90 * 60_000)
        XCTAssertEqual(withDays.trailingSpanMs(now: now, timeZone: taipei), 2 * 3_600_000)
        XCTAssertEqual(withDays.trailingAverageAgentTimeMs(now: now, timeZone: taipei), 90 * 60_000)
        XCTAssertEqual(withDays.trailingMaxAgentTimeMs(now: now, timeZone: taipei), 90 * 60_000)
    }

    func testTrailingAverageAndMaxIgnoreIdleDaysAndOlderHistory() {
        let old = DayActivity(
            day: ActivityDayKey(year: 2026, month: 6, day: 1),
            requestCount: 2,
            tokens: 10,
            spanMs: 8 * 3_600_000,
            estimatedActiveMs: 8 * 3_600_000
        )
        let short = DayActivity(
            day: ActivityDayKey(year: 2026, month: 8, day: 10),
            requestCount: 1,
            tokens: 4,
            spanMs: 30 * 60_000,
            estimatedActiveMs: 30 * 60_000
        )
        let long = DayActivity(
            day: ActivityDayKey(year: 2026, month: 8, day: 20),
            requestCount: 4,
            tokens: 20,
            spanMs: 3 * 3_600_000,
            estimatedActiveMs: 90 * 60_000
        )
        let insights = ActivityAnalyzer.analyze(
            seats: [.init(seatID: .seat1, requests: [], truncated: false, reportedTotal: 0)],
            scope: .account(.seat1),
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: taipei,
            now: date(2026, 8, 31, 12, 0),
            requestedSeatCount: 1
        )
        let withDays = ActivityInsights(
            scope: insights.scope,
            range: insights.range,
            timeZoneIdentifier: insights.timeZoneIdentifier,
            idleGap: insights.idleGap,
            hourOfDayCounts: insights.hourOfDayCounts,
            hourOfDayTokens: insights.hourOfDayTokens,
            dayOfWeekCounts: insights.dayOfWeekCounts,
            days: [old, short, long],
            totalRequests: 7,
            totalTokens: 34,
            activeDayCount: 3,
            medianDailySpanMs: insights.medianDailySpanMs,
            medianEstimatedActiveMs: insights.medianEstimatedActiveMs,
            coverage: insights.coverage,
            monthOverMonth: nil,
            estimatedActiveIsPerSeatSum: false
        )
        let now = date(2026, 8, 31, 12, 0)
        XCTAssertEqual(withDays.trailingAverageAgentTimeMs(now: now, timeZone: taipei), 60 * 60_000)
        XCTAssertEqual(withDays.trailingMaxAgentTimeMs(now: now, timeZone: taipei), 90 * 60_000)
    }

    // MARK: - Fixtures

    private func req(ms: Int64, tokens: TokenBreakdown? = TokenBreakdown(input: 1, output: 1, cacheWrite: 0, cacheRead: 0)) -> ActivityRequest {
        ActivityRequest(
            timestampMs: ms,
            model: "composer-2.5-fast",
            kind: .includedInUltra,
            tokens: tokens,
            usageValueCents: 1,
            onDemandChargedCents: nil,
            isHeadless: false,
            isTokenBasedCall: true
        )
    }

    private func dayMs(_ y: Int, _ m: Int, _ d: Int, _ hour: Int, _ minute: Int) -> Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = taipei
        var parts = DateComponents()
        parts.year = y
        parts.month = m
        parts.day = d
        parts.hour = hour
        parts.minute = minute
        let date = calendar.date(from: parts)!
        return Int64(date.timeIntervalSince1970 * 1000.0)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int, _ minute: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(dayMs(y, m, d, hour, minute)) / 1000.0)
    }
}
