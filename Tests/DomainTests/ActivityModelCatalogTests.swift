import CursorBarDomain
import XCTest

final class ActivityModelCatalogTests: XCTestCase {
    private var taipei: TimeZone { TimeZone(identifier: "Asia/Taipei")! }

    func testListsEveryModelAndRanksByUsageValue() {
        let requests = [
            request(
                ms: dayMs(2026, 6, 2, 10, 0),
                model: "composer-2.5-fast",
                tokens: 1_000,
                usageValue: 20,
                onDemand: nil
            ),
            request(
                ms: dayMs(2026, 6, 2, 11, 0),
                model: "claude-4.5-opus-high-thinking",
                tokens: 500,
                usageValue: 80,
                onDemand: 10
            ),
            request(
                ms: dayMs(2026, 6, 3, 9, 0),
                model: "composer-2.5-fast",
                tokens: 1_000,
                usageValue: 20,
                onDemand: nil
            ),
        ]
        let catalog = ActivityModelCatalog.build(requests: requests, timeZone: taipei)
        XCTAssertEqual(catalog.models.map(\.modelIntent), [
            "claude-4.5-opus-high-thinking",
            "composer-2.5-fast",
        ])
        XCTAssertEqual(catalog.models[0].displayName, "Claude 4.5 Opus High Thinking")
        XCTAssertEqual(catalog.models[0].requestCount, 1)
        XCTAssertEqual(catalog.models[0].usageValueCents, 80)
        XCTAssertEqual(catalog.models[0].onDemandChargedCents, 10)
        XCTAssertEqual(catalog.models[0].subsidizedCents, 70)
        XCTAssertEqual(catalog.models[1].requestCount, 2)
        XCTAssertEqual(catalog.models[1].tokens, 2_000)
        XCTAssertEqual(catalog.models[1].subsidizedCents, 40)
        XCTAssertEqual(catalog.totalUsageValueCents, 120)
        XCTAssertEqual(catalog.totalOnDemandChargedCents, 10)
        XCTAssertEqual(catalog.totalSubsidizedCents, 110)
    }

    func testImpliedRateIsUsageValuePerMillionTokens() {
        let rate = ActivityModelCatalog.impliedCentsPerMillion(usageValueCents: 250, tokens: 500_000)
        XCTAssertEqual(rate, 500)
        XCTAssertEqual(
            ActivityModelCatalog.formatRate(500),
            "\(ActivityCostSemantics.formatCents(500)) / 1M"
        )
        XCTAssertNil(ActivityModelCatalog.impliedCentsPerMillion(usageValueCents: 10, tokens: 0))
        XCTAssertNil(ActivityModelCatalog.impliedCentsPerMillion(usageValueCents: 0, tokens: 100))
    }

    func testMonthRatesShowPricingChange() {
        let requests = [
            request(
                ms: dayMs(2026, 4, 10, 12, 0),
                model: "gpt-5.2",
                tokens: 1_000_000,
                usageValue: 400,
                onDemand: nil
            ),
            request(
                ms: dayMs(2026, 8, 10, 12, 0),
                model: "gpt-5.2",
                tokens: 1_000_000,
                usageValue: 250,
                onDemand: 40
            ),
        ]
        let catalog = ActivityModelCatalog.build(requests: requests, timeZone: taipei)
        let row = try! XCTUnwrap(catalog.models.first)
        XCTAssertEqual(row.months.count, 2)
        XCTAssertEqual(row.months[0].month, YearMonth(year: 2026, month: 4))
        XCTAssertEqual(row.months[0].impliedCentsPerMillion, 400)
        XCTAssertEqual(row.months[1].impliedCentsPerMillion, 250)
        let timeline = try! XCTUnwrap(
            ActivityModelCatalog.rateTimelineCaption(for: row, timeZone: taipei)
        )
        XCTAssertTrue(timeline.contains(ActivityModelCatalog.formatRate(400)))
        XCTAssertTrue(timeline.contains(ActivityModelCatalog.formatRate(250)))
        XCTAssertTrue(timeline.contains("→"))
    }

    func testSectionsByFamilyFollowsFamilyOrderAndSkipsEmpty() {
        let rows = [
            pricingRow(intent: "mystery-slug"),
            pricingRow(intent: "o3"),
            pricingRow(intent: "composer-2"),
            pricingRow(intent: "cursor-small"),
            pricingRow(intent: "gpt-5"),
            pricingRow(intent: "cursor-grok-4.5-high"),
        ]
        let sections = ActivityModelCatalog.sectionsByFamily(rows)
        XCTAssertEqual(sections.map(\.family), [
            .composer,
            .grok,
            .gpt,
            .oSeries,
            .cursor,
            .other,
        ])
        XCTAssertFalse(sections.contains { $0.family == .claude })
        XCTAssertEqual(sections.first { $0.family == .grok }?.rows.map(\.modelIntent), [
            "cursor-grok-4.5-high",
        ])
        XCTAssertEqual(sections.first { $0.family == .cursor }?.rows.map(\.modelIntent), [
            "cursor-small",
        ])
    }

    func testAnalyzerAttachesCatalog() {
        let insights = ActivityAnalyzer.analyze(
            seats: [
                .init(
                    seatID: .seat1,
                    requests: [
                        request(
                            ms: dayMs(2026, 8, 10, 9, 0),
                            model: "o3",
                            tokens: 2_000,
                            usageValue: 30,
                            onDemand: nil
                        ),
                    ],
                    truncated: false,
                    reportedTotal: 1
                ),
            ],
            scope: .account(.seat1),
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: taipei,
            requestedSeatCount: 1
        )
        XCTAssertEqual(insights.modelCatalog.models.count, 1)
        XCTAssertEqual(insights.modelCatalog.models[0].modelIntent, "o3")
        XCTAssertEqual(insights.modelCatalog.totalSubsidizedCents, 30)
    }

    private func pricingRow(intent: String) -> ModelPricingRow {
        ModelPricingRow(
            modelIntent: intent,
            displayName: ModelDisplayNames.displayName(for: intent),
            requestCount: 1,
            tokens: 1,
            usageValueCents: 1,
            onDemandChargedCents: 0,
            usageValueEventCount: 1,
            onDemandEventCount: 0,
            months: []
        )
    }

    private func request(
        ms: Int64,
        model: String,
        tokens: Int64,
        usageValue: Int64?,
        onDemand: Int64?
    ) -> ActivityRequest {
        ActivityRequest(
            timestampMs: ms,
            model: model,
            kind: onDemand == nil ? .includedInUltra : .usageBased,
            tokens: TokenBreakdown(input: tokens, output: 0, cacheWrite: 0, cacheRead: 0),
            usageValueCents: usageValue,
            onDemandChargedCents: onDemand,
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
}
