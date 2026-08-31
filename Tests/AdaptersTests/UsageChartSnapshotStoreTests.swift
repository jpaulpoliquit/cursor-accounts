import CursorBarAdapters
import CursorBarDomain
import XCTest

final class UsageChartSnapshotStoreTests: XCTestCase {
    func testRoundTripAndEmptyLoad() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-chart-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageChartSnapshotStore(applicationSupportRoot: root)
        XCTAssertNil(store.load())

        let snapshot = UsageChartSnapshot(
            series: UsageSeries(
                scope: .allAccounts,
                rangeStart: UsageDayKey(year: 2026, month: 8, day: 1),
                rangeEnd: UsageDayKey(year: 2026, month: 8, day: 2),
                points: [
                    UsagePoint(
                        day: UsageDayKey(year: 2026, month: 8, day: 1),
                        tokens: 42,
                        spendCents: nil,
                        coverage: .complete
                    ),
                ],
                coverage: PartialCoverage(includedAccountCount: 1, requestedAccountCount: 1),
                costAvailable: false
            ),
            tokenSummary: UsageTokenSummary(
                scope: .allAccounts,
                range: .month(YearMonth(year: 2026, month: 8)),
                totals: .zero,
                topModels: [],
                coverage: PartialCoverage(includedAccountCount: 1, requestedAccountCount: 1),
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            insights: nil,
            scope: .allAccounts,
            range: .month(YearMonth(year: 2026, month: 8)),
            metric: .tokens,
            settledAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        store.write(snapshot)
        XCTAssertEqual(store.load(), snapshot)
        let data = try Data(contentsOf: root.appendingPathComponent("usage-chart.json"))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("accessToken"))
        XCTAssertFalse(json.contains("Bearer"))
        store.write(nil)
        XCTAssertNil(store.load())
    }
}
