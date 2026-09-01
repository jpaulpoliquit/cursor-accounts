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
        CursorProfileStat(
            label: "Avg day · 30 days",
            value: averageDayValue
        )
        .help(averageDayHelp)
        CursorProfileStat(
            label: "Max day · 30 days",
            value: maxDayValue
        )
        .help(maxDayHelp)
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

    private var averageDayValue: String {
        guard let insights,
              let ms = insights.trailingAverageAgentTimeMs(now: now, timeZone: timeZone)
        else { return "—" }
        return ActivityInsights.durationCompact(ms)
    }

    private var maxDayValue: String {
        guard let insights,
              let ms = insights.trailingMaxAgentTimeMs(now: now, timeZone: timeZone)
        else { return "—" }
        return ActivityInsights.durationCompact(ms)
    }

    private var averageDayHelp: String {
        let base = insights?.agentTimeHelp ?? "Estimated time agents were active."
        return "\(base) Average on days you were active in the last 30 local days."
    }

    private var maxDayHelp: String {
        let base = insights?.agentTimeHelp ?? "Estimated time agents were active."
        return "\(base) Longest single day in the last 30 local days."
    }
}
