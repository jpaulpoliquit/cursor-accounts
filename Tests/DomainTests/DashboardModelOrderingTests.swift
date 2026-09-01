import CursorBarDomain
import XCTest

final class DashboardModelOrderingTests: XCTestCase {
    func testGroupByTriggerMatchesNewtonCopy() {
        XCTAssertEqual(DashboardModelGroup.none.menuTitle, "No grouping")
        XCTAssertEqual(DashboardModelGroup.none.triggerLabel, "No grouping")
        XCTAssertEqual(DashboardModelGroup.family.menuTitle, "Family")
        XCTAssertEqual(DashboardModelGroup.family.triggerLabel, "By family")
        XCTAssertEqual(ModelDisplayNames.familyGroupCountLabel(1), "1 model")
        XCTAssertEqual(ModelDisplayNames.familyGroupCountLabel(5), "5 models")
        XCTAssertEqual(ModelDisplayNames.familyGroupCountLabel(17), "17 models")
        XCTAssertNotEqual(ModelDisplayNames.Family.grok.title, "Grok")
        XCTAssertEqual(ModelDisplayNames.Family.grok.title, "Cursor Grok")
    }

    func testTokensDescendingPutsLargestFirst() {
        let small = row(name: "A", tokens: 10, requests: 4, value: 100, charged: 20, rate: 5)
        let large = row(name: "B", tokens: 90, requests: 2, value: 50, charged: 10, rate: 8)
        let sorted = DashboardModelOrdering.sorted(
            [small, large],
            by: .tokens,
            direction: .descending
        )
        XCTAssertEqual(sorted.map(\.displayName), ["B", "A"])
    }

    func testMissingRateSortsLastWhenDescending() {
        let priced = row(name: "Priced", tokens: 1_000_000, requests: 1, value: 100, charged: 0, rate: 100)
        let unknown = row(name: "Unknown", tokens: 0, requests: 1, value: 0, charged: 0, rate: nil)
        let sorted = DashboardModelOrdering.sorted(
            [unknown, priced],
            by: .rate,
            direction: .descending
        )
        XCTAssertEqual(sorted.map(\.displayName), ["Priced", "Unknown"])
    }

    private func row(
        name: String,
        tokens: Int64,
        requests: Int,
        value: Int64,
        charged: Int64,
        rate: Int64?
    ) -> ModelPricingRow {
        ModelPricingRow(
            modelIntent: name.lowercased(),
            displayName: name,
            requestCount: requests,
            tokens: tokens,
            usageValueCents: rate == nil ? 0 : value,
            onDemandChargedCents: charged,
            usageValueEventCount: 1,
            onDemandEventCount: 0,
            months: []
        )
    }
}
