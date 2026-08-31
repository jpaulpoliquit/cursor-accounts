import CursorBarAdapters
import CursorBarDomain
import Foundation

/// Verify-only sentinels written to an isolated Application Support root.
enum VerifyUsageCacheSeed {
    static let planName = "verify-cache-ultra"
    static let autoPercent = 17.0
    static let tokenSum: Int64 = 424_242
    static let seededMarkerPath = "/tmp/cursorbar-usage-cache-seeded"

    static var isRequested: Bool { argumentURL() != nil }

    static func argumentURL() -> URL? {
        for arg in CommandLine.arguments {
            if arg.hasPrefix("--seed-usage-cache=") {
                let path = String(arg.dropFirst("--seed-usage-cache=".count))
                return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return nil
    }

    static func write(to root: URL) {
        let cards = UsageCardSnapshotStore(applicationSupportRoot: root)
        let charts = UsageChartSnapshotStore(applicationSupportRoot: root)
        cards.write([.seat1: cardSnapshot()])
        charts.write(chartSnapshot())
        try? "ok".write(to: URL(fileURLWithPath: seededMarkerPath), atomically: true, encoding: .utf8)
    }

    static func cardSnapshot() -> SeatUsageSnapshot {
        SeatUsageSnapshot(
            seatID: .seat1,
            plan: PlanInfo(name: planName, includedAmountCents: AmountCents(cents: 20_000)),
            period: PeriodUsageDetail(
                usage: PeriodUsage(
                    autoPercentUsed: PercentUsed(unchecked: autoPercent),
                    apiPercentUsed: PercentUsed(unchecked: 20),
                    totalPercentUsed: PercentUsed(unchecked: 18)
                ),
                displayMessage: nil,
                spendLimitUsage: SpendLimitUsage(individualUsed: AmountCents(cents: 0))
            ),
            hardLimit: .off,
            credits: .absent,
            policy: UsagePolicy(canAdjustOnDemand: true),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func chartSnapshot() -> UsageChartSnapshot {
        let day = UsageDayKey(year: 2026, month: 8, day: 1)
        return UsageChartSnapshot(
            series: UsageSeries(
                scope: .allAccounts,
                rangeStart: day,
                rangeEnd: day,
                points: [
                    UsagePoint(
                        day: day,
                        tokens: tokenSum,
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
    }
}
