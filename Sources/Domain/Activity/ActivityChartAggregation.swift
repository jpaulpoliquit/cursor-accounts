import Foundation

/// Chart point for the Insights daily/period activity bars.
public struct ActivityChartPoint: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { label }
    public let label: String
    public let accessibilityLabel: String
    public let requestCount: Int
    public let tokens: Int64

    public init(label: String, accessibilityLabel: String, requestCount: Int, tokens: Int64) {
        self.label = label
        self.accessibilityLabel = accessibilityLabel
        self.requestCount = requestCount
        self.tokens = tokens
    }
}

public enum ActivityChartAggregation {
    /// Prefer daily bars when the range is short; collapse to YearMonth bars for long All Time windows.
    public static func points(
        from insights: ActivityInsights,
        locale: Locale = .current
    ) -> [ActivityChartPoint] {
        let days = insights.days
        guard !days.isEmpty else { return [] }
        if days.count <= 62 {
            return days.map { day in
                ActivityChartPoint(
                    label: shortDayLabel(day.day),
                    accessibilityLabel: "\(day.day.isoDate), \(day.requestCount) requests",
                    requestCount: day.requestCount,
                    tokens: day.tokens
                )
            }
        }
        var buckets: [YearMonth: (requests: Int, tokens: Int64)] = [:]
        for day in days {
            let month = YearMonth(year: day.day.year, month: day.day.month)
            var existing = buckets[month] ?? (0, 0)
            existing.requests += day.requestCount
            existing.tokens += day.tokens
            buckets[month] = existing
        }
        return buckets.keys.sorted().map { month in
            let value = buckets[month]!
            let title = month.localizedTitle(locale: locale)
            return ActivityChartPoint(
                label: title,
                accessibilityLabel: "\(title), \(value.requests) requests",
                requestCount: value.requests,
                tokens: value.tokens
            )
        }
    }

    private static func shortDayLabel(_ day: ActivityDayKey) -> String {
        String(format: "%d/%d", day.month, day.day)
    }
}
