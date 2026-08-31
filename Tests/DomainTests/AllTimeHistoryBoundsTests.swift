import CursorBarDomain
import XCTest

final class AllTimeHistoryBoundsTests: XCTestCase {
    func testAllAccountsUsesEarliestResolvedStart() {
        let today = UsageDayKey(year: 2026, month: 8, day: 10)
        let bounds = AllTimeHistoryBounds(
            endDay: today,
            perSeat: [
                .seat1: .resolved(startDay: UsageDayKey(year: 2026, month: 7, day: 6)),
                .seat2: .resolved(startDay: UsageDayKey(year: 2025, month: 2, day: 1)),
                .seat3: .resolved(startDay: UsageDayKey(year: 2026, month: 8, day: 2)),
                .seat4: .resolved(startDay: UsageDayKey(year: 2025, month: 5, day: 7)),
            ]
        )
        let window = bounds.chartWindow(for: .allAccounts)
        XCTAssertEqual(window?.start, UsageDayKey(year: 2025, month: 2, day: 1))
        XCTAssertEqual(window?.end, today)
    }

    func testAccountScopeUsesThatSeatStart() {
        let today = UsageDayKey(year: 2026, month: 8, day: 10)
        let bounds = AllTimeHistoryBounds(
            endDay: today,
            perSeat: [
                .seat1: .resolved(startDay: UsageDayKey(year: 2026, month: 7, day: 6)),
                .seat2: .resolved(startDay: UsageDayKey(year: 2025, month: 2, day: 1)),
            ]
        )
        XCTAssertEqual(
            bounds.chartWindow(for: .account(.seat1))?.start,
            UsageDayKey(year: 2026, month: 7, day: 6)
        )
        XCTAssertEqual(
            bounds.fetchStart(for: .seat1, chartStart: UsageDayKey(year: 2025, month: 2, day: 1)),
            UsageDayKey(year: 2026, month: 7, day: 6)
        )
    }

    func testPartialBoundDoesNotDropSuccessfulSeats() {
        let today = UsageDayKey(year: 2026, month: 8, day: 10)
        let bounds = AllTimeHistoryBoundsResolver.merge(
            seats: [.seat1, .seat2],
            createdAtBySeat: [
                .seat2: Date(timeIntervalSince1970: TimeInterval(
                    UsageDayKey(year: 2025, month: 2, day: 1).utcMidnightMs
                ) / 1000.0),
            ],
            failedSeats: [.seat1],
            today: today
        )
        XCTAssertEqual(bounds?.earliestResolvedStart, UsageDayKey(year: 2025, month: 2, day: 1))
        XCTAssertTrue(bounds?.isPartial == true)
        XCTAssertNotNil(bounds?.boundCoverageCaption)
    }

    func testRefreshingEndRecomputesToday() {
        let bounds = AllTimeHistoryBounds(
            endDay: UsageDayKey(year: 2026, month: 8, day: 1),
            perSeat: [.seat1: .resolved(startDay: UsageDayKey(year: 2026, month: 1, day: 1))]
        )
        let next = bounds.refreshingEnd(to: UsageDayKey(year: 2026, month: 8, day: 10))
        XCTAssertEqual(next.endDay.day, 10)
        XCTAssertEqual(next.start(for: .seat1)?.month, 1)
    }

    func testNearestDaySkipsMissingCoverage() {
        let d1 = UsageDayKey(year: 2026, month: 1, day: 1)
        let d2 = UsageDayKey(year: 2026, month: 1, day: 2)
        let d3 = UsageDayKey(year: 2026, month: 1, day: 3)
        let points = [
            UsagePoint(
                day: d1,
                tokens: 10,
                spendCents: nil,
                coverage: .complete,
                contributions: [DayAccountContribution(seatID: .seat1, tokens: 10, spendCents: nil)]
            ),
            UsagePoint(
                day: d2,
                tokens: 20,
                spendCents: nil,
                coverage: .complete,
                contributions: [DayAccountContribution(seatID: .seat1, tokens: 20, spendCents: nil)]
            ),
            UsagePoint(day: d3, tokens: 30, spendCents: nil, coverage: .missing),
        ]
        let index = UsageChartInspectionIndex(
            points: points,
            accountLabels: [.seat1: "Alpha"],
            includeContributions: true
        )
        XCTAssertEqual(index.inspections.count, 2)
        let near = index.nearest(
            to: Date(timeIntervalSince1970: TimeInterval(d2.utcMidnightMs) / 1000.0 + 3_600)
        )
        XCTAssertEqual(near?.day, d2)
        XCTAssertNil(index.inspection(for: d3))
    }

    func testContributionOrderShareAndPrivacyLabels() throws {
        let day = UsageDayKey(year: 2026, month: 6, day: 1)
        let point = UsagePoint(
            day: day,
            tokens: 100,
            spendCents: nil,
            coverage: .complete,
            contributions: [
                DayAccountContribution(seatID: .seat1, tokens: 40, spendCents: nil),
                DayAccountContribution(seatID: .seat2, tokens: 60, spendCents: nil),
            ]
        )
        let index = UsageChartInspectionIndex(
            points: [point],
            accountLabels: [.seat1: "A", .seat2: "B"],
            includeContributions: true
        )
        let rows = try XCTUnwrap(index.inspections.first?.contributions)
        XCTAssertEqual(rows.map(\.seatID), [.seat2, .seat1])
        XCTAssertEqual(rows.map(\.tokens).reduce(0, +), 100)
        XCTAssertEqual(rows[0].share + rows[1].share, 1.0, accuracy: 0.0001)
        XCTAssertFalse(rows.contains(where: { $0.label.contains("@") }))
    }

    func testCostInspectionUsesSpendCentsSharesNotTokenShares() throws {
        let day = UsageDayKey(year: 2026, month: 6, day: 1)
        let point = UsagePoint(
            day: day,
            tokens: 1_000,
            spendCents: 300,
            coverage: .complete,
            contributions: [
                DayAccountContribution(seatID: .seat1, tokens: 100, spendCents: 100),
                DayAccountContribution(seatID: .seat2, tokens: 900, spendCents: 200),
            ]
        )
        let tokenIndex = UsageChartInspectionIndex(
            points: [point],
            accountLabels: [.seat1: "Work", .seat2: "Personal"],
            includeContributions: true,
            metric: .tokens
        )
        let costIndex = UsageChartInspectionIndex(
            points: [point],
            accountLabels: [.seat1: "Work", .seat2: "Personal"],
            includeContributions: true,
            metric: .costCents
        )
        let tokenInspection = try XCTUnwrap(tokenIndex.inspections.first)
        let costInspection = try XCTUnwrap(costIndex.inspections.first)
        let tokenWork = try XCTUnwrap(tokenInspection.contributions.first(where: { $0.seatID == .seat1 }))
        let costWork = try XCTUnwrap(costInspection.contributions.first(where: { $0.seatID == .seat1 }))
        XCTAssertEqual(tokenWork.share, 0.1, accuracy: 0.0001)
        XCTAssertEqual(costWork.share, 100.0 / 300.0, accuracy: 0.0001)
        XCTAssertEqual(costInspection.tooltipTotalText(metric: .costCents), CostCountFormat.accessibilityCents(300))
        XCTAssertTrue(costInspection.tooltipRowText(costWork, metric: .costCents).contains("$1.00"))
        let a11y = costInspection.accessibilityLabel(metric: .costCents)
        XCTAssertTrue(a11y.contains("$3.00") || a11y.contains("3.00"))
        XCTAssertFalse(a11y.contains("1,000 tokens"))
    }

    func testCostInspectionHonestWhenSpendMissing() throws {
        let day = UsageDayKey(year: 2026, month: 6, day: 1)
        let point = UsagePoint(
            day: day,
            tokens: 500,
            spendCents: nil,
            coverage: .partial,
            contributions: [
                DayAccountContribution(seatID: .seat1, tokens: 500, spendCents: nil),
            ]
        )
        let index = UsageChartInspectionIndex(
            points: [point],
            accountLabels: [.seat1: "Work"],
            includeContributions: true,
            metric: .costCents
        )
        let inspection = try XCTUnwrap(index.inspections.first)
        XCTAssertTrue(inspection.costCompositionUnavailable)
        XCTAssertEqual(inspection.tooltipTotalText(metric: .costCents), "Cost unavailable")
        XCTAssertTrue(inspection.accessibilityLabel(metric: .costCents).contains("total cost unavailable"))
    }

    func testRevealThenMaskRebuildDropsEmailFromTooltipAndAccessibility() throws {
        let day = UsageDayKey(year: 2026, month: 6, day: 1)
        let point = UsagePoint(
            day: day,
            tokens: 50,
            spendCents: nil,
            coverage: .complete,
            contributions: [
                DayAccountContribution(seatID: .seat1, tokens: 50, spendCents: nil),
            ]
        )
        let email = "revealed.user@example.com"
        let revealed = UsageChartInspectionIndex(
            points: [point],
            accountLabels: [.seat1: email],
            includeContributions: true
        )
        XCTAssertTrue(revealed.inspections.contains(where: { inspection in
            inspection.contributions.contains(where: { $0.label == email })
                || inspection.accessibilityLabel(metric: .tokens).contains(email)
        }))

        let maskedLabel = AccountLabelResolver.resolve(
            policy: .maskEmail,
            source: .init(
                seatID: .seat1,
                email: Email(email),
                displayName: DisplayName("john 5")
            )
        ).text
        let masked = UsageChartInspectionIndex(
            points: [point],
            accountLabels: [.seat1: maskedLabel],
            includeContributions: true
        )
        let inspection = try XCTUnwrap(masked.inspections.first)
        XCTAssertEqual(inspection.contributions.first?.label, maskedLabel)
        XCTAssertFalse(inspection.contributions.contains(where: { $0.label.contains("@") }))
        XCTAssertFalse(inspection.contributions.contains(where: { $0.label.contains("revealed.user") }))
        let accessibility = inspection.accessibilityLabel(metric: .tokens)
        XCTAssertFalse(accessibility.contains("@"))
        XCTAssertFalse(accessibility.contains("revealed.user"))
        XCTAssertFalse(accessibility.contains(email))
    }

    func testTooltipOmitsZeroAndSingleContributionRows() {
        let day = UsageDayKey(year: 2026, month: 4, day: 21)
        let winner = UsageDayContributionRow(
            seatID: .seat1,
            label: "John",
            tokens: 246,
            spendCents: nil,
            share: 1
        )
        let zero = UsageDayContributionRow(
            seatID: .seat2,
            label: "Other",
            tokens: 0,
            spendCents: nil,
            share: 0
        )
        let single = UsageDayInspection(
            day: day,
            totalTokens: 246,
            spendCents: nil,
            coverage: .complete,
            contributions: [winner, zero]
        )
        XCTAssertTrue(single.tooltipContributions(metric: .tokens).isEmpty)

        let split = UsageDayInspection(
            day: day,
            totalTokens: 300,
            spendCents: nil,
            coverage: .complete,
            contributions: [
                winner,
                UsageDayContributionRow(
                    seatID: .seat2,
                    label: "Other",
                    tokens: 54,
                    spendCents: nil,
                    share: 0.18
                ),
            ]
        )
        XCTAssertEqual(split.tooltipContributions(metric: .tokens).map(\.label), ["John", "Other"])
    }

    func testInspectionAccessibilityUsesFullTokenCount() {
        let inspection = UsageDayInspection(
            day: UsageDayKey(year: 2026, month: 6, day: 1),
            totalTokens: 1_200_000,
            spendCents: nil,
            coverage: .complete,
            contributions: []
        )
        let label = inspection.accessibilityLabel(metric: .tokens, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(label.contains("1") && (label.contains("200") || label.contains("1,200,000")))
        XCTAssertFalse(label.lowercased().contains("input"))
    }
}
