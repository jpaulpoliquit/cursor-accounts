import Foundation

/// Last visible chart + insights. Credential-free. No raw event arrays.
public struct UsageChartSnapshot: Codable, Sendable, Equatable {
    public var series: UsageSeries?
    public var tokenSummary: UsageTokenSummary?
    public var insights: ActivityInsights?
    public var scope: UsageScope
    public var range: UsageRange
    public var metric: UsageMetric
    public var settledAt: Date?

    public init(
        series: UsageSeries?,
        tokenSummary: UsageTokenSummary?,
        insights: ActivityInsights?,
        scope: UsageScope,
        range: UsageRange,
        metric: UsageMetric,
        settledAt: Date?
    ) {
        self.series = series
        self.tokenSummary = tokenSummary
        self.insights = insights
        self.scope = scope
        self.range = range
        self.metric = metric
        self.settledAt = settledAt
    }

    public var isWellFormed: Bool {
        guard let insights else { return true }
        return insights.hourOfDayCounts.count == 24
            && insights.hourOfDayTokens.count == 24
            && insights.dayOfWeekCounts.count == 7
    }
}
