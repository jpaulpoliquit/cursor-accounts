import CursorBarDomain
import SwiftUI

struct DashboardUsageStatsRow: View {
    let insights: ActivityInsights
    let thisSeatID: SeatID?
    let thisSeatTitle: String

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
        let headline = insights.tokenHeadline(thisSeatID: thisSeatID)
        CursorProfileStat(
            label: "Tokens · this account",
            value: compact(headline.thisAccount)
        )
        .accessibilityHint(thisSeatTitle)
        CursorProfileStat(
            label: "Tokens · all accounts",
            value: compact(headline.allAccounts)
        )
        CursorProfileStat(
            label: "Requests",
            value: TokenCountFormat.compact(Int64(insights.totalRequests))
        )
        CursorProfileStat(
            label: "Active days",
            value: "\(insights.activeDayCount)"
        )
    }

    private func compact(_ tokens: Int64?) -> String {
        guard let tokens else { return "—" }
        return TokenCountFormat.compact(tokens)
    }
}
