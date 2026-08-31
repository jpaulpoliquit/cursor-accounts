import CursorBarDomain
import SwiftUI

struct DashboardUsageStatsRow: View {
    let insights: ActivityInsights

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                stats
            }
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 16
            ) {
                stats
            }
        }
    }

    @ViewBuilder
    private var stats: some View {
        CursorProfileStat(
            label: "Requests",
            value: TokenCountFormat.compact(Int64(insights.totalRequests))
        )
        CursorProfileStat(
            label: "Tokens",
            value: TokenCountFormat.compact(insights.totalTokens)
        )
        CursorProfileStat(
            label: "Active days",
            value: "\(insights.activeDayCount)"
        )
        CursorProfileStat(
            label: "Usage value",
            value: ActivityCostSemantics.formatCents(insights.money.usageValueCents)
        )
    }
}
