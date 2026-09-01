import Foundation

/// GitHub-style activity dots. Chart daily tokens are the source of truth;
/// request insights only add counts when that history has been fetched.
public enum ActivityHeatmapDays {
    public static func merge(
        series: UsageSeries?,
        insights: ActivityInsights?
    ) -> [DayActivity] {
        var byDay: [ActivityDayKey: DayActivity] = [:]

        if let series {
            for point in series.points where point.hasDisplayableUsage {
                let day = ActivityDayKey(
                    year: point.day.year,
                    month: point.day.month,
                    day: point.day.day
                )
                byDay[day] = DayActivity(
                    day: day,
                    requestCount: 0,
                    tokens: point.tokens,
                    spanMs: 0,
                    estimatedActiveMs: 0,
                    contributions: point.contributions.map {
                        ActivitySeatContribution(
                            seatID: $0.seatID,
                            requestCount: 0,
                            tokens: $0.tokens
                        )
                    }
                )
            }
        }

        if let insights {
            for incoming in insights.days {
                if let existing = byDay[incoming.day] {
                    byDay[incoming.day] = DayActivity(
                        day: incoming.day,
                        requestCount: incoming.requestCount,
                        tokens: max(existing.tokens, incoming.tokens),
                        spanMs: incoming.spanMs,
                        estimatedActiveMs: incoming.estimatedActiveMs,
                        firstRequestMs: incoming.firstRequestMs,
                        lastRequestMs: incoming.lastRequestMs,
                        contributions: incoming.contributions.isEmpty
                            ? existing.contributions
                            : incoming.contributions
                    )
                } else {
                    byDay[incoming.day] = incoming
                }
            }
        }

        return byDay.keys.sorted().map { byDay[$0]! }
    }
}
