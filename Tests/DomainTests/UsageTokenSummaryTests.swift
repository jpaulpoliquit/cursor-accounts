import CursorBarDomain
import XCTest

final class UsageTokenSummaryTests: XCTestCase {
    func testCanonicalTotalIsSumOfFourDisjointBuckets() {
        let buckets = TokenBucketCounts(input: 10, output: 20, cacheWrite: 30, cacheRead: 40)
        XCTAssertEqual(buckets?.total, 100)
    }

    func testRejectsNegativeBuckets() {
        XCTAssertNil(TokenBucketCounts(input: -1, output: 0, cacheWrite: 0, cacheRead: 0))
        XCTAssertNil(TokenBucketCounts(input: 0, output: -2, cacheWrite: 0, cacheRead: 0))
        XCTAssertNil(TokenBucketCounts(input: 0, output: 0, cacheWrite: -3, cacheRead: 0))
        XCTAssertNil(TokenBucketCounts(input: 0, output: 0, cacheWrite: 0, cacheRead: -4))
    }

    func testRejectsOverflowOnInitAndAdd() {
        let huge = TokenBucketCounts(input: Int64.max, output: 0, cacheWrite: 0, cacheRead: 0)
        XCTAssertNotNil(huge)
        XCTAssertNil(TokenBucketCounts(input: Int64.max, output: 1, cacheWrite: 0, cacheRead: 0))
        let one = TokenBucketCounts(input: 1, output: 0, cacheWrite: 0, cacheRead: 0)!
        XCTAssertNil(huge!.adding(one))
    }

    func testTopFiveRankingAndTieBreakByModelIntent() {
        let models = [
            row("zeta", 50),
            row("alpha", 100),
            row("beta", 100),
            row("gamma", 80),
            row("delta", 70),
            row("epsilon", 60),
            row("eta", 10),
        ]
        let ranked = UsageTokenSummaryAggregator.rankedTopModels(from: models, summaryTotal: 470)
        XCTAssertEqual(ranked.map(\.model.modelIntent), ["alpha", "beta", "gamma", "delta", "epsilon"])
        XCTAssertEqual(ranked[0].share, 100.0 / 470.0, accuracy: 0.0001)
    }

    func testShareIsZeroWhenSummaryTotalIsZero() {
        XCTAssertEqual(UsageTokenSummaryAggregator.share(modelTotal: 10, summaryTotal: 0), 0)
        let ranked = UsageTokenSummaryAggregator.rankedTopModels(
            from: [row("solo", 0)],
            summaryTotal: 0
        )
        XCTAssertEqual(ranked.first?.share, 0)
    }

    func testDisplayNameMapAndHumanizedFallback() {
        XCTAssertEqual(
            ModelDisplayNames.displayName(for: "cursor-grok-4.5-high-fast"),
            "Cursor Grok 4.5 High Fast"
        )
        XCTAssertEqual(
            ModelDisplayNames.displayName(for: "brand-new-model-9"),
            "Brand New Model 9"
        )
        XCTAssertEqual(ModelDisplayNames.displayName(for: "gpt-experimental"), "GPT Experimental")
    }

    func testAllAccountsSumsAbsoluteFieldsAndRecomputesShares() {
        let seat1 = SeatUsageTokenSummary(
            seatID: .seat1,
            totals: TokenBucketCounts(input: 10, output: 0, cacheWrite: 0, cacheRead: 0)!,
            models: [row("alpha", 10), row("beta", 5)]
        )
        let seat2 = SeatUsageTokenSummary(
            seatID: .seat2,
            totals: TokenBucketCounts(input: 30, output: 0, cacheWrite: 0, cacheRead: 0)!,
            models: [row("alpha", 30), row("gamma", 20)]
        )
        let summary = UsageTokenSummaryAggregator.aggregate(
            successful: [seat1, seat2],
            requestedAccountCount: 2,
            scope: .allAccounts,
            range: .month(YearMonth(year: 2026, month: 8)),
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(summary.totals.total, 40)
        XCTAssertEqual(summary.topModels.map(\.model.modelIntent), ["alpha", "gamma", "beta"])
        XCTAssertEqual(summary.topModels[0].model.buckets.total, 40)
        XCTAssertEqual(summary.topModels[0].share, 1.0, accuracy: 0.0001)
        XCTAssertFalse(summary.coverage.isPartial)
    }

    func testRanksLinesNotVariantLeaves() {
        let models = [
            row("cursor-grok-4.5-high-fast", 60),
            row("cursor-grok-4.5-high", 40),
            row("cursor-grok-4.6-xhigh-fast", 50),
            row("composer-2", 45),
            row("composer-2.5-fast", 42),
            row("gpt-5.6-sol-medium", 29),
            row("mystery-slug", 10),
        ]
        let lines = UsageTokenSummaryAggregator.rankedTopLines(from: models, summaryTotal: 276)
        XCTAssertEqual(lines.map(\.title), [
            "Cursor Grok 4.5",
            "Cursor Grok 4.6",
            "Composer 2",
            "Composer 2.5",
            "GPT 5.6",
        ])
        XCTAssertEqual(lines[0].tokens, 100)
        XCTAssertEqual(lines[0].share, 100.0 / 276.0, accuracy: 0.0001)
        XCTAssertEqual(lines[0].variants.map(\.model.modelIntent), [
            "cursor-grok-4.5-high-fast",
            "cursor-grok-4.5-high",
        ])
        let leaves = UsageTokenSummaryAggregator.rankedTopModels(from: models, summaryTotal: 276)
        XCTAssertEqual(leaves.map(\.model.modelIntent), [
            "cursor-grok-4.5-high-fast",
            "cursor-grok-4.5-high",
            "cursor-grok-4.6-xhigh-fast",
            "composer-2",
            "composer-2.5-fast",
            "gpt-5.6-sol-medium",
        ])
    }

    func testPartialCoverageWhenOneSeatFails() {
        let seat1 = SeatUsageTokenSummary(
            seatID: .seat1,
            totals: TokenBucketCounts(input: 7, output: 0, cacheWrite: 0, cacheRead: 0)!,
            models: [row("solo", 7)]
        )
        let summary = UsageTokenSummaryAggregator.aggregate(
            successful: [seat1],
            requestedAccountCount: 2,
            scope: .allAccounts,
            range: .month(YearMonth(year: 2026, month: 8))
        )
        XCTAssertTrue(summary.coverage.isPartial)
        XCTAssertEqual(summary.coverage.caption, "1 of 2 accounts")
        XCTAssertEqual(summary.totals.total, 7)
    }

    private func row(_ intent: String, _ total: Int64) -> ModelUsageRow {
        ModelUsageRow(
            modelIntent: intent,
            displayName: ModelDisplayNames.displayName(for: intent),
            buckets: TokenBucketCounts(input: total, output: 0, cacheWrite: 0, cacheRead: 0)!
        )
    }
}
