import CursorBarDomain
import XCTest

final class ActivityCostAndInspectionTests: XCTestCase {
    func testOnDemandChargedParsesDollarStrings() {
        XCTAssertEqual(ActivityCostSemantics.onDemandChargedCents(fromUsageBasedCosts: "$1.23"), 123)
        XCTAssertEqual(ActivityCostSemantics.onDemandChargedCents(fromUsageBasedCosts: "0.40"), 40)
        XCTAssertNil(ActivityCostSemantics.onDemandChargedCents(fromUsageBasedCosts: "-"))
        XCTAssertNil(ActivityCostSemantics.onDemandChargedCents(fromUsageBasedCosts: "n/a"))
        XCTAssertNil(ActivityCostSemantics.onDemandChargedCents(fromUsageBasedCosts: nil))
    }

    func testUsageValueRoundsChargedCents() {
        XCTAssertEqual(ActivityCostSemantics.usageValueCents(fromChargedCents: 1.5), 2)
        XCTAssertEqual(ActivityCostSemantics.usageValueCents(fromChargedCents: 0), 0)
        XCTAssertNil(ActivityCostSemantics.usageValueCents(fromChargedCents: -1))
    }

    func testAnalyzerMoneySeparatesUsageValueAndOnDemand() {
        let tz = TimeZone(identifier: "Asia/Taipei")!
        let requests = [
            ActivityRequest(
                timestampMs: 1_700_000_000_000,
                model: "a",
                kind: .usageBased,
                tokens: TokenBreakdown(input: 1, output: 1, cacheWrite: 0, cacheRead: 0),
                usageValueCents: 10,
                onDemandChargedCents: 25,
                isHeadless: false,
                isTokenBasedCall: true
            ),
            ActivityRequest(
                timestampMs: 1_700_000_100_000,
                model: "b",
                kind: .includedInUltra,
                tokens: TokenBreakdown(input: 2, output: 2, cacheWrite: 0, cacheRead: 0),
                usageValueCents: 5,
                onDemandChargedCents: nil,
                isHeadless: false,
                isTokenBasedCall: true
            ),
        ]
        let insights = ActivityAnalyzer.analyze(
            seats: [
                ActivityAnalyzer.SeatEvents(
                    seatID: .seat1,
                    requests: requests,
                    truncated: false,
                    reportedTotal: 2
                ),
            ],
            scope: .account(.seat1),
            range: .month(YearMonth(year: 2023, month: 11)),
            timeZone: tz,
            requestedSeatCount: 1
        )
        XCTAssertEqual(insights.money.usageValueCents, 15)
        XCTAssertEqual(insights.money.onDemandChargedCents, 25)
        XCTAssertEqual(insights.money.onDemandEventCount, 1)
        XCTAssertEqual(insights.money.usageValueEventCount, 2)
    }

    func testInspectionIndexUsesHourTokensAndDayFirstLast() {
        let tz = TimeZone(identifier: "Asia/Taipei")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        func ms(_ hour: Int, minute: Int = 0) -> Int64 {
            var c = DateComponents()
            c.year = 2026
            c.month = 8
            c.day = 10
            c.hour = hour
            c.minute = minute
            return Int64(calendar.date(from: c)!.timeIntervalSince1970 * 1000)
        }
        let requests = [
            ActivityRequest(
                timestampMs: ms(9),
                model: "a",
                kind: .includedInUltra,
                tokens: TokenBreakdown(input: 100, output: 0, cacheWrite: 0, cacheRead: 0),
                usageValueCents: 1,
                onDemandChargedCents: nil,
                isHeadless: false,
                isTokenBasedCall: true
            ),
            ActivityRequest(
                timestampMs: ms(9, minute: 20),
                model: "a",
                kind: .includedInUltra,
                tokens: TokenBreakdown(input: 50, output: 0, cacheWrite: 0, cacheRead: 0),
                usageValueCents: 1,
                onDemandChargedCents: nil,
                isHeadless: false,
                isTokenBasedCall: true
            ),
            ActivityRequest(
                timestampMs: ms(14),
                model: "b",
                kind: .includedInUltra,
                tokens: TokenBreakdown(input: 10, output: 0, cacheWrite: 0, cacheRead: 0),
                usageValueCents: 1,
                onDemandChargedCents: nil,
                isHeadless: false,
                isTokenBasedCall: true
            ),
        ]
        let insights = ActivityAnalyzer.analyze(
            seats: [
                ActivityAnalyzer.SeatEvents(
                    seatID: .seat1,
                    requests: requests,
                    truncated: false,
                    reportedTotal: 3
                ),
            ],
            scope: .account(.seat1),
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: tz,
            requestedSeatCount: 1
        )
        let index = ActivityInspectionIndex(insights: insights)
        XCTAssertEqual(index.hour(nearest: 9)?.requestCount, 2)
        XCTAssertEqual(index.hour(nearest: 9)?.tokens, 150)
        XCTAssertEqual(index.periods.count, 1)
        XCTAssertEqual(index.periods[0].requestCount, 3)
        XCTAssertNotNil(index.periods[0].firstRequestMs)
        XCTAssertNotNil(index.periods[0].lastRequestMs)
        XCTAssertGreaterThan(index.periods[0].spanMs, 0)
        XCTAssertGreaterThan(index.periods[0].estimatedActiveMs, 0)
    }

    func testTopModelsCopyIsRangeAware() {
        let month = TopModelsCopy.title(for: .month(YearMonth(year: 2026, month: 8)))
        XCTAssertTrue(month.hasPrefix("Top models ·"))
        XCTAssertFalse(month.localizedCaseInsensitiveContains("available history"))
        let allTime = TopModelsCopy.title(
            for: .allTime(
                start: UsageDayKey(year: 2024, month: 1, day: 1),
                end: UsageDayKey(year: 2026, month: 8, day: 10)
            )
        )
        XCTAssertEqual(allTime, "Top models · available history")
    }

    func testMultiAccountContributionsSurfaceInInspection() {
        let tz = TimeZone(identifier: "Asia/Taipei")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        var c = DateComponents()
        c.year = 2026
        c.month = 8
        c.day = 10
        c.hour = 10
        let stamp = Int64(calendar.date(from: c)!.timeIntervalSince1970 * 1000)
        func req(_ seatTokens: Int64) -> ActivityRequest {
            ActivityRequest(
                timestampMs: stamp,
                model: "m",
                kind: .includedInUltra,
                tokens: TokenBreakdown(input: seatTokens, output: 0, cacheWrite: 0, cacheRead: 0),
                usageValueCents: nil,
                onDemandChargedCents: nil,
                isHeadless: false,
                isTokenBasedCall: true
            )
        }
        let insights = ActivityAnalyzer.analyze(
            seats: [
                .init(seatID: .seat1, requests: [req(10)], truncated: false, reportedTotal: 1),
                .init(seatID: .seat2, requests: [req(20)], truncated: false, reportedTotal: 1),
            ],
            scope: .allAccounts,
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: tz,
            requestedSeatCount: 2
        )
        let index = ActivityInspectionIndex(
            insights: insights,
            accountLabels: [.seat1: "Work", .seat2: "Personal"]
        )
        XCTAssertEqual(index.periods.count, 1)
        XCTAssertTrue(index.periods[0].contributionLabels.contains("Work: 1 requests"))
        XCTAssertTrue(index.periods[0].contributionLabels.contains("Personal: 1 requests"))
    }

    func testRevealThenMaskRebuildDropsEmailFromInsightsInspection() {
        let tz = TimeZone(identifier: "Asia/Taipei")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        var c = DateComponents()
        c.year = 2026
        c.month = 8
        c.day = 10
        c.hour = 10
        let stamp = Int64(calendar.date(from: c)!.timeIntervalSince1970 * 1000)
        func req(_ tokens: Int64) -> ActivityRequest {
            ActivityRequest(
                timestampMs: stamp,
                model: "m",
                kind: .includedInUltra,
                tokens: TokenBreakdown(input: tokens, output: 0, cacheWrite: 0, cacheRead: 0),
                usageValueCents: nil,
                onDemandChargedCents: nil,
                isHeadless: false,
                isTokenBasedCall: true
            )
        }
        // Multi-seat All Accounts is what surfaces contribution labels in inspection.
        let insights = ActivityAnalyzer.analyze(
            seats: [
                .init(seatID: .seat1, requests: [req(10)], truncated: false, reportedTotal: 1),
                .init(seatID: .seat2, requests: [req(20)], truncated: false, reportedTotal: 1),
            ],
            scope: .allAccounts,
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: tz,
            requestedSeatCount: 2
        )
        let email = "insights.user@example.com"
        let revealed = ActivityInspectionIndex(
            insights: insights,
            accountLabels: [.seat1: email, .seat2: "Personal"]
        )
        XCTAssertTrue(revealed.periods.contains(where: { period in
            period.contributionLabels.contains(where: { $0.contains(email) })
        }))

        let maskedLabel = AccountLabelResolver.resolve(
            policy: .maskEmail,
            source: .init(
                seatID: .seat1,
                email: Email(email),
                displayName: DisplayName("work")
            )
        ).text
        let masked = ActivityInspectionIndex(
            insights: insights,
            accountLabels: [.seat1: maskedLabel, .seat2: "Personal"]
        )
        for period in masked.periods {
            XCTAssertFalse(period.contributionLabels.contains(where: { $0.contains("@") }))
            XCTAssertFalse(period.contributionLabels.contains(where: { $0.contains("insights.user") }))
            XCTAssertFalse(period.tooltipLines(timeZone: tz).contains(where: { $0.contains(email) }))
            XCTAssertFalse(period.accessibilityLabel(timeZone: tz).contains(email))
            XCTAssertTrue(period.contributionLabels.contains(where: { $0.contains(maskedLabel) }))
        }
    }
}
