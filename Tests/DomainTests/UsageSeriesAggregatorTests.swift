import CursorBarDomain
import XCTest

final class UsageSeriesAggregatorTests: XCTestCase {
    func testCategoryRowsSumIntoDay() {
        let day = UsageDayKey(year: 2026, month: 8, day: 1)
        let rows = [
            DailySpendCategoryRow(day: day, category: "a", spendCents: nil, totalTokens: 10),
            DailySpendCategoryRow(day: day, category: "b", spendCents: nil, totalTokens: 15),
        ]
        let series = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: rows,
            rangeStart: day,
            rangeEnd: day
        )
        XCTAssertEqual(series.points.count, 1)
        XCTAssertEqual(series.points[0].tokens, 25)
        XCTAssertNil(series.points[0].spendCents)
        XCTAssertFalse(series.costAvailable)
    }

    func testSuccessfulMissingDayBecomesExplicitZero() {
        let start = UsageDayKey(year: 2026, month: 8, day: 1)
        let mid = UsageDayKey(year: 2026, month: 8, day: 2)
        let end = UsageDayKey(year: 2026, month: 8, day: 3)
        let rows = [
            DailySpendCategoryRow(day: start, category: "m", spendCents: nil, totalTokens: 9),
            DailySpendCategoryRow(day: end, category: "m", spendCents: nil, totalTokens: 4),
        ]
        let series = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: rows,
            rangeStart: start,
            rangeEnd: end
        )
        XCTAssertEqual(series.points.map(\.tokens), [9, 0, 4])
        XCTAssertEqual(series.points[1].day, mid)
        XCTAssertEqual(series.points[1].coverage, .complete)
    }

    func testFailedSeatMarksPartialAndNeverFakeZeroContribution() {
        let day = UsageDayKey(year: 2026, month: 8, day: 10)
        let ok = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: [DailySpendCategoryRow(day: day, category: "m", spendCents: nil, totalTokens: 100)],
            rangeStart: day,
            rangeEnd: day
        )
        let series = UsageSeriesAggregator.aggregate(
            successful: [ok],
            requestedAccountCount: 3,
            scope: .allAccounts,
            rangeStart: day,
            rangeEnd: day
        )
        XCTAssertTrue(series.coverage.isPartial)
        XCTAssertEqual(series.coverage.caption, "1 of 3 accounts")
        XCTAssertEqual(series.points[0].tokens, 100)
        XCTAssertEqual(series.points[0].coverage, .partial)
    }

    func testAllAccountsAlignmentIsLast30UTCDays() {
        let today = UsageDayKey(year: 2026, month: 8, day: 10)
        let range = UsageSeriesAggregator.allAccountsRange(today: today)
        let days = UsageDayKey.days(from: range.start, through: range.end)
        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(range.end, today)
        XCTAssertEqual(range.start, UsageDayKey(year: 2026, month: 7, day: 12))
    }

    func testIndividualCycleRangeClampsToToday() {
        let cycle = BillingCycleBounds(
            startMs: UsageDayKey(year: 2026, month: 8, day: 1).utcMidnightMs,
            endMs: UsageDayKey(year: 2026, month: 9, day: 1).utcMidnightMs
        )
        let today = UsageDayKey(year: 2026, month: 8, day: 10)
        let range = UsageSeriesAggregator.individualRange(cycle: cycle, today: today)
        XCTAssertEqual(range.start, UsageDayKey(year: 2026, month: 8, day: 1))
        XCTAssertEqual(range.end, today)
    }

    func testPercentagesStructurallyAbsentFromAggregator() {
        let source = try! String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Domain/UsageSeriesAggregator.swift")
        )
        XCTAssertFalse(source.contains("PercentUsed"))
        XCTAssertFalse(source.contains("autoPercent"))
        XCTAssertFalse(source.contains("apiPercent"))
        XCTAssertFalse(source.contains("totalPercent"))
    }

    func testCostAvailableOnlyWhenSpendCentsPresent() {
        let day = UsageDayKey(year: 2026, month: 8, day: 1)
        let tokensOnly = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: [DailySpendCategoryRow(day: day, category: "m", spendCents: nil, totalTokens: 1)],
            rangeStart: day,
            rangeEnd: day
        )
        XCTAssertFalse(tokensOnly.costAvailable)
        XCTAssertEqual(tokensOnly.points[0].spendCents, nil)

        let withCost = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: [DailySpendCategoryRow(day: day, category: "m", spendCents: 12, totalTokens: 1)],
            rangeStart: day,
            rangeEnd: day
        )
        XCTAssertTrue(withCost.costAvailable)
        XCTAssertEqual(withCost.points[0].spendCents, 12)
        XCTAssertEqual(withCost.availableMetricsViaSeries.costAvailable, true)
    }

    func testAccessibilityDescriptorIncludesMetricRangeScopePartial() {
        let start = UsageDayKey(year: 2026, month: 8, day: 1)
        let end = UsageDayKey(year: 2026, month: 8, day: 2)
        let text = UsageChartAccessibility.descriptor(
            metric: .tokens,
            scopeLabel: "All Accounts",
            rangeStart: start,
            rangeEnd: end,
            coverage: PartialCoverage(includedAccountCount: 2, requestedAccountCount: 3),
            pointCount: 2
        )
        XCTAssertTrue(text.contains("Daily tokens"))
        XCTAssertTrue(text.contains("All Accounts"))
        XCTAssertTrue(text.contains("2026-08-01"))
        XCTAssertTrue(text.contains("2026-08-02"))
        XCTAssertTrue(text.contains("2 of 3 accounts"))
    }

    func testAllFailedProducesMissingCoverageNeverFakeCompleteZero() {
        let day = UsageDayKey(year: 2026, month: 8, day: 10)
        let series = UsageSeriesAggregator.aggregate(
            successful: [],
            requestedAccountCount: 2,
            scope: .allAccounts,
            rangeStart: day,
            rangeEnd: day
        )
        XCTAssertEqual(series.coverage.includedAccountCount, 0)
        XCTAssertEqual(series.coverage.requestedAccountCount, 2)
        XCTAssertTrue(series.coverage.isPartial)
        XCTAssertEqual(series.points[0].coverage, .missing)
        XCTAssertEqual(series.points[0].tokens, 0)
        XCTAssertFalse(series.costAvailable)
    }

    func testOneAccountAllAccountsValuesEqualIndividualWhileMetadataDiffers() {
        let start = UsageDayKey(year: 2026, month: 8, day: 1)
        let end = UsageDayKey(year: 2026, month: 8, day: 3)
        let seat = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: [
                DailySpendCategoryRow(day: start, category: "m", spendCents: nil, totalTokens: 11),
                DailySpendCategoryRow(day: end, category: "m", spendCents: nil, totalTokens: 7),
            ],
            rangeStart: start,
            rangeEnd: end
        )
        let allAccounts = UsageSeriesAggregator.aggregate(
            successful: [seat],
            requestedAccountCount: 1,
            scope: .allAccounts,
            rangeStart: start,
            rangeEnd: end
        )
        let individual = UsageSeriesAggregator.aggregate(
            successful: [seat],
            requestedAccountCount: 1,
            scope: .account(.seat1),
            rangeStart: start,
            rangeEnd: end
        )
        XCTAssertEqual(allAccounts.points.map(\.tokens), individual.points.map(\.tokens))
        XCTAssertEqual(allAccounts.points.map(\.spendCents), individual.points.map(\.spendCents))
        XCTAssertNotEqual(allAccounts.scope, individual.scope)
        XCTAssertEqual(allAccounts.scope, .allAccounts)
        XCTAssertEqual(individual.scope, .account(.seat1))
        XCTAssertEqual(allAccounts.coverage, individual.coverage)
    }

    func testScopeLabelsUseAccountLabelResolverUnderMask() {
        let email = Email("secret.user@example.com")!
        let masked = AccountLabelResolver.resolve(
            policy: .maskEmail,
            source: .init(seatID: .seat1, email: email, displayName: DisplayName("john 5"))
        )
        let label = UsageScopeLabels.label(for: .account(.seat1), accountLabel: masked)
        XCTAssertEqual(label, "john 5")
        XCTAssertFalse(label.contains("@"))
        XCTAssertFalse(label.contains("secret.user"))
        XCTAssertEqual(UsageScopeLabels.label(for: .allAccounts, accountLabel: nil), "All Accounts")
    }

    func testAvailableMetricsHideCostWhenSpendCentsAbsent() {
        let day = UsageDayKey(year: 2026, month: 8, day: 1)
        let tokensOnly = UsageSeries(
            scope: .allAccounts,
            rangeStart: day,
            rangeEnd: day,
            points: [UsagePoint(day: day, tokens: 1, spendCents: nil, coverage: .complete)],
            coverage: PartialCoverage(includedAccountCount: 1, requestedAccountCount: 1),
            costAvailable: false
        )
        XCTAssertEqual(tokensOnly.availableMetrics, [.tokens])
        XCTAssertEqual(UsageMetric.tokens.chartTitle, "Daily tokens")
    }

    func testPreStartDaysAreExplicitZeroAndContributionsSumToTotal() {
        let start = UsageDayKey(year: 2026, month: 1, day: 1)
        let accountStart = UsageDayKey(year: 2026, month: 1, day: 3)
        let end = UsageDayKey(year: 2026, month: 1, day: 3)
        let seat1 = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: [
                DailySpendCategoryRow(day: end, category: "m", spendCents: nil, totalTokens: 40),
            ],
            rangeStart: start,
            rangeEnd: end,
            accountStart: accountStart
        )
        let seat2 = UsageSeriesAggregator.seatSeries(
            seatID: .seat2,
            rows: [
                DailySpendCategoryRow(day: start, category: "m", spendCents: nil, totalTokens: 10),
                DailySpendCategoryRow(day: end, category: "m", spendCents: nil, totalTokens: 60),
            ],
            rangeStart: start,
            rangeEnd: end,
            accountStart: start
        )
        XCTAssertEqual(seat1.points[0].tokens, 0)
        XCTAssertEqual(seat1.points[0].coverage, .complete)
        let series = UsageSeriesAggregator.aggregate(
            successful: [seat1, seat2],
            requestedAccountCount: 2,
            scope: .allAccounts,
            rangeStart: start,
            rangeEnd: end
        )
        let last = series.points.last!
        XCTAssertEqual(last.tokens, 100)
        XCTAssertEqual(last.contributions.map(\.tokens).reduce(0, +), 100)
        XCTAssertEqual(Set(last.contributions.map(\.seatID)), [.seat1, .seat2])
    }

    func testAllTimeDisplayStartsAtFirstUsageAndDropsLeadingZeros() {
        let created = UsageDayKey(year: 2026, month: 2, day: 1)
        let firstUsage = UsageDayKey(year: 2026, month: 6, day: 1)
        let end = UsageDayKey(year: 2026, month: 8, day: 14)
        let seat = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: [
                DailySpendCategoryRow(day: firstUsage, category: "m", spendCents: nil, totalTokens: 40),
                DailySpendCategoryRow(day: end, category: "m", spendCents: nil, totalTokens: 8),
            ],
            rangeStart: created,
            rangeEnd: end,
            accountStart: created
        )
        let series = UsageSeriesAggregator.aggregate(
            successful: [seat],
            requestedAccountCount: 1,
            scope: .account(.seat1),
            rangeStart: created,
            rangeEnd: end
        )
        XCTAssertEqual(series.rangeStart, created)
        XCTAssertEqual(series.points.first?.tokens, 0)
        let displayed = series.forDisplay(
            in: .allTime(start: created, end: end)
        )
        XCTAssertEqual(displayed.rangeStart, firstUsage)
        XCTAssertEqual(displayed.firstDisplayableDay, firstUsage)
        XCTAssertEqual(displayed.points.first?.day, firstUsage)
        XCTAssertEqual(displayed.points.first?.tokens, 40)
        XCTAssertFalse(displayed.points.contains { $0.day < firstUsage })
        XCTAssertTrue(displayed.points.contains { $0.day == end && $0.tokens == 8 })
        let monthKept = series.forDisplay(in: .month(YearMonth(year: 2026, month: 2)))
        XCTAssertEqual(monthKept.rangeStart, created)
        XCTAssertEqual(monthKept.points.first?.tokens, 0)
    }

    func testAllAccountsDisplayStartIsEarliestUsageAmongSeats() {
        let created = UsageDayKey(year: 2026, month: 2, day: 1)
        let firstB = UsageDayKey(year: 2026, month: 5, day: 10)
        let firstA = UsageDayKey(year: 2026, month: 6, day: 1)
        let end = UsageDayKey(year: 2026, month: 8, day: 14)
        let seatA = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: [
                DailySpendCategoryRow(day: firstA, category: "m", spendCents: nil, totalTokens: 10),
            ],
            rangeStart: created,
            rangeEnd: end,
            accountStart: created
        )
        let seatB = UsageSeriesAggregator.seatSeries(
            seatID: .seat2,
            rows: [
                DailySpendCategoryRow(day: firstB, category: "m", spendCents: nil, totalTokens: 20),
                DailySpendCategoryRow(day: firstA, category: "m", spendCents: nil, totalTokens: 5),
            ],
            rangeStart: created,
            rangeEnd: end,
            accountStart: created
        )
        let series = UsageSeriesAggregator.aggregate(
            successful: [seatA, seatB],
            requestedAccountCount: 2,
            scope: .allAccounts,
            rangeStart: created,
            rangeEnd: end
        )
        let displayed = series.forDisplay(
            in: .allTime(start: created, end: end)
        )
        XCTAssertEqual(displayed.rangeStart, firstB)
        XCTAssertEqual(displayed.coverage.includedAccountCount, 2)
        XCTAssertEqual(displayed.points.first?.tokens, 20)
        let june = displayed.points.first { $0.day == firstA }
        XCTAssertEqual(june?.tokens, 15)
        XCTAssertEqual(Set(june?.contributions.map(\.seatID) ?? []), [.seat1, .seat2])
        XCTAssertFalse(displayed.points.contains { $0.day < firstB })
    }

    func testUncoveredDaysAreMissingNotFabricatedZero() {
        let start = UsageDayKey(year: 2026, month: 1, day: 1)
        let end = UsageDayKey(year: 2026, month: 1, day: 2)
        let series = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: [
                DailySpendCategoryRow(day: end, category: "m", spendCents: nil, totalTokens: 9),
            ],
            rangeStart: start,
            rangeEnd: end,
            uncoveredDays: [start]
        )
        XCTAssertEqual(series.points[0].coverage, .missing)
        XCTAssertEqual(series.points[0].tokens, 0)
        XCTAssertEqual(series.points[1].coverage, .complete)
        XCTAssertEqual(series.points[1].tokens, 9)
        XCTAssertTrue(series.availableMetricsViaSeries.hasPlottablePoints)
    }

    func testAllMissingRangeIsNotPlottable() {
        let start = UsageDayKey(year: 2026, month: 1, day: 1)
        let end = UsageDayKey(year: 2026, month: 1, day: 3)
        let series = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: [],
            rangeStart: start,
            rangeEnd: end,
            uncoveredDays: Set(UsageDayKey.days(from: start, through: end))
        ).availableMetricsViaSeries
        XCTAssertFalse(series.points.isEmpty)
        XCTAssertFalse(series.hasPlottablePoints)
        XCTAssertTrue(series.plottablePoints.isEmpty)
    }
}

private extension SeatUsageSeries {
    var availableMetricsViaSeries: UsageSeries {
        UsageSeries(
            scope: .account(seatID),
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            points: points,
            coverage: PartialCoverage(includedAccountCount: 1, requestedAccountCount: 1),
            costAvailable: costAvailable
        )
    }
}
