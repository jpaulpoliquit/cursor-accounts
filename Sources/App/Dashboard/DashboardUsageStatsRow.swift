import CursorBarDomain
import SwiftUI

struct DashboardUsageStatsRow: View {
    let insights: ActivityInsights?
    var now: Date = Date()

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: CursorProfile.sectionSpacing) {
                stats
            }
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: CursorProfile.cardPadding
            ) {
                stats
            }
        }
    }

    @ViewBuilder
    private var stats: some View {
        CursorProfileStat(
            label: "Agent time · all time",
            value: allTimeValue
        )
        .help(allTimeHelp)
        CursorProfileStat(
            label: "Agent time · 30 days",
            value: thirtyDayValue
        )
        .help(thirtyDayHelp)
    }

    private var timeZone: TimeZone {
        guard let insights else { return .current }
        return TimeZone(identifier: insights.timeZoneIdentifier) ?? .current
    }

    private var allTimeValue: String {
        guard let insights else { return "—" }
        return ActivityInsights.durationCompact(insights.totalAgentTimeMs)
    }

    private var thirtyDayValue: String {
        guard let insights else { return "—" }
        return ActivityInsights.durationCompact(
            insights.trailingAgentTimeMs(now: now, timeZone: timeZone)
        )
    }

    private var allTimeHelp: String {
        let base = insights?.agentTimeHelp ?? "Estimated time agents were active."
        return "\(base) All loaded history."
    }

    private var thirtyDayHelp: String {
        let base = insights?.agentTimeHelp ?? "Estimated time agents were active."
        return "\(base) Last 30 local days."
    }
}
