import CursorBarDomain
import XCTest

final class AgentAccountListTests: XCTestCase {
    func testRowsUseNicknameAndUpcomingRenewals() throws {
        let soon = Date(timeIntervalSince1970: 1_800_000_000)
        let past = Date(timeIntervalSince1970: 1_000)
        let work = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            planName: "ultra",
            resetDate: soon,
            autoPercent: PercentUsed(unchecked: 10),
            identityPolicy: .maskEmail,
            userLabel: SeatUserLabel("Work")
        )
        let old = SeatPresentation(
            seatID: .seat2,
            label: .displayName(DisplayName("Ada")!),
            auth: .signedIn,
            resetDate: past,
            identityPolicy: .maskEmail
        )
        let email = Email("jp@example.com")!
        let rows = AgentAccountList.rows(from: [work, old], emails: [.seat1: email])
        XCTAssertEqual(rows.map(\.label), ["Work", "Ada"])
        XCTAssertEqual(rows.first?.userLabel, "Work")
        XCTAssertEqual(rows.first?.identity, "john 5")
        XCTAssertEqual(rows.first?.email, "jp@example.com")
        XCTAssertNil(rows.last?.email)
        let upcoming = AgentAccountList.upcomingRenewals(
            from: rows,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(upcoming.map(\.seatID), ["seat1"])
        let table = AgentAccountList.textTable(rows, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(table.contains("Work"))
        XCTAssertTrue(table.contains("john 5"))
        XCTAssertTrue(table.contains("jp@example.com"))
        XCTAssertTrue(table.contains("Email"))
        XCTAssertTrue(table.contains("Name"))
        let lines = table.split(separator: "\n")
        XCTAssertGreaterThanOrEqual(lines.count, 3)
        XCTAssertEqual(Set(lines.map(\.count)).count, 1)
        let encoded = try AgentAccountList.json(rows)
        XCTAssertTrue(encoded.contains("jp@example.com"))
    }

    func testUsageTokensFromSummary() {
        let summary = UsageTokenSummary(
            scope: .allAccounts,
            range: .month(YearMonth(year: 2026, month: 8)),
            totals: TokenBucketCounts(input: 1000, output: 200, cacheWrite: 0, cacheRead: 50)!,
            topModels: [
                RankedModelUsage(
                    model: ModelUsageRow(
                        modelIntent: "cursor-grok-4.5-high",
                        displayName: "Cursor Grok 4.5 High",
                        buckets: TokenBucketCounts(input: 1000, output: 200, cacheWrite: 0, cacheRead: 50)!
                    ),
                    share: 1
                )
            ],
            coverage: PartialCoverage(includedAccountCount: 1, requestedAccountCount: 1),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let snapshot = UsageChartSnapshot(
            series: nil,
            tokenSummary: summary,
            insights: nil,
            scope: .allAccounts,
            range: .month(YearMonth(year: 2026, month: 8)),
            metric: .tokens,
            settledAt: nil
        )
        let tokens = AgentUsageReport.make(snapshot: snapshot, group: .tokens)
        XCTAssertTrue(tokens.available)
        XCTAssertTrue(tokens.text.contains("1.3K") || tokens.text.contains("1250") || tokens.text.contains("1K"))
        let models = AgentUsageReport.make(snapshot: snapshot, group: .models)
        XCTAssertTrue(models.text.contains("Grok") || models.text.contains("Cursor"))
        let missing = AgentUsageReport.make(snapshot: nil, group: .activity)
        XCTAssertFalse(missing.available)
    }
}
