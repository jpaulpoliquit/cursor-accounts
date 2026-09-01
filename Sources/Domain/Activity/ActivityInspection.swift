import Foundation

/// Hover / VoiceOver payload for one local hour bin.
public struct ActivityHourInspection: Sendable, Equatable, Hashable {
    public let hour: Int
    public let requestCount: Int
    public let tokens: Int64

    public init(hour: Int, requestCount: Int, tokens: Int64) {
        self.hour = hour
        self.requestCount = requestCount
        self.tokens = tokens
    }

    public var accessibilityLabel: String {
        "\(ActivityInsights.clockLabel(hour)), \(TokenCountFormat.grouped(requestCount)) requests, \(TokenCountFormat.accessibility(tokens)) tokens"
    }

    public var tooltipLines: [String] {
        [
            ActivityInsights.clockLabel(hour),
            "\(TokenCountFormat.grouped(requestCount)) requests",
            "\(TokenCountFormat.compact(tokens)) tokens",
        ]
    }
}

/// Hover / VoiceOver payload for one daily (or monthly-aggregated) activity bar.
public struct ActivityPeriodInspection: Sendable, Equatable, Hashable {
    public let label: String
    public let accessibilityDate: String
    public let requestCount: Int
    public let tokens: Int64
    public let firstRequestMs: Int64?
    public let lastRequestMs: Int64?
    public let spanMs: Int64
    public let estimatedActiveMs: Int64
    public let contributionLabels: [String]
    public let isMonthBucket: Bool

    public init(
        label: String,
        accessibilityDate: String,
        requestCount: Int,
        tokens: Int64,
        firstRequestMs: Int64?,
        lastRequestMs: Int64?,
        spanMs: Int64,
        estimatedActiveMs: Int64,
        contributionLabels: [String] = [],
        isMonthBucket: Bool = false
    ) {
        self.label = label
        self.accessibilityDate = accessibilityDate
        self.requestCount = requestCount
        self.tokens = tokens
        self.firstRequestMs = firstRequestMs
        self.lastRequestMs = lastRequestMs
        self.spanMs = spanMs
        self.estimatedActiveMs = estimatedActiveMs
        self.contributionLabels = contributionLabels
        self.isMonthBucket = isMonthBucket
    }

    public func accessibilityLabel(timeZone: TimeZone) -> String {
        var parts = [
            accessibilityDate,
            "\(TokenCountFormat.grouped(requestCount)) requests",
            "\(TokenCountFormat.accessibility(tokens)) tokens",
            "estimated agent-active \(ActivityInsights.durationAccessibility(estimatedActiveMs))",
        ]
        if !isMonthBucket, let first = firstRequestMs, let last = lastRequestMs {
            parts.append("first \(Self.clock(first, timeZone: timeZone))")
            parts.append("last \(Self.clock(last, timeZone: timeZone))")
        }
        parts.append(contentsOf: contributionLabels)
        return parts.joined(separator: ", ")
    }

    public func tooltipLines(timeZone: TimeZone, idleGap _: IdleGapPolicy = .thirtyMinutes) -> [String] {
        var lines = [
            accessibilityDate,
            "\(TokenCountFormat.grouped(requestCount)) requests · \(TokenCountFormat.compact(tokens)) tokens",
        ]
        if isMonthBucket {
            if estimatedActiveMs > 0 {
                lines.append("Est. active \(ActivityInsights.durationCompact(estimatedActiveMs))")
            }
            return lines
        }
        if let first = firstRequestMs, let last = lastRequestMs {
            lines.append(
                "First \(Self.clock(first, timeZone: timeZone)) → Last \(Self.clock(last, timeZone: timeZone))"
            )
        }
        if requestCount > 1, estimatedActiveMs > 0 {
            lines.append("Est. active \(ActivityInsights.durationCompact(estimatedActiveMs))")
        } else if requestCount == 1 {
            lines.append("Single request")
        }
        return lines
    }

    private static func clock(_ ms: Int64, timeZone: TimeZone) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

/// Precomputed hour + period indexes for Insights chart hover.
public struct ActivityInspectionIndex: Sendable, Equatable {
    public let hours: [ActivityHourInspection]
    public let periods: [ActivityPeriodInspection]
    public let usesMonthBuckets: Bool

    public init(
        insights: ActivityInsights,
        locale: Locale = .current,
        accountLabels: [SeatID: String] = [:]
    ) {
        self.hours = (0..<24).map { hour in
            ActivityHourInspection(
                hour: hour,
                requestCount: insights.hourOfDayCounts[hour],
                tokens: insights.hourOfDayTokens[hour]
            )
        }

        let usesMonths = insights.days.count > 62
        self.usesMonthBuckets = usesMonths
        let chartPoints = ActivityChartAggregation.points(from: insights, locale: locale)

        if usesMonths {
            var byMonth: [YearMonth: DayActivity] = [:]
            for day in insights.days {
                let month = YearMonth(year: day.day.year, month: day.day.month)
                if let existing = byMonth[month] {
                    byMonth[month] = DayActivity(
                        day: existing.day,
                        requestCount: existing.requestCount + day.requestCount,
                        tokens: existing.tokens + day.tokens,
                        spanMs: existing.spanMs + day.spanMs,
                        estimatedActiveMs: existing.estimatedActiveMs + day.estimatedActiveMs,
                        firstRequestMs: Self.minOptional(existing.firstRequestMs, day.firstRequestMs),
                        lastRequestMs: Self.maxOptional(existing.lastRequestMs, day.lastRequestMs)
                    )
                } else {
                    byMonth[month] = day
                }
            }
            self.periods = chartPoints.map { point in
                let month = byMonth.keys.first(where: {
                    $0.localizedTitle(locale: locale) == point.label
                })
                let day = month.flatMap { byMonth[$0] }
                return ActivityPeriodInspection(
                    label: point.label,
                    accessibilityDate: month?.localizedTitle(locale: locale) ?? point.accessibilityLabel,
                    requestCount: day?.requestCount ?? point.requestCount,
                    tokens: day?.tokens ?? point.tokens,
                    firstRequestMs: day?.firstRequestMs,
                    lastRequestMs: day?.lastRequestMs,
                    spanMs: day?.spanMs ?? 0,
                    estimatedActiveMs: day?.estimatedActiveMs ?? 0,
                    contributionLabels: Self.contributionLines(
                        day?.contributions ?? [],
                        accountLabels: accountLabels
                    ),
                    isMonthBucket: true
                )
            }
        } else {
            self.periods = zip(chartPoints, insights.days).map { point, day in
                ActivityPeriodInspection(
                    label: point.label,
                    accessibilityDate: day.day.isoDate,
                    requestCount: day.requestCount,
                    tokens: day.tokens,
                    firstRequestMs: day.firstRequestMs,
                    lastRequestMs: day.lastRequestMs,
                    spanMs: day.spanMs,
                    estimatedActiveMs: day.estimatedActiveMs,
                    contributionLabels: Self.contributionLines(
                        day.contributions,
                        accountLabels: accountLabels
                    )
                )
            }
        }
    }

    public func hour(nearest raw: Double) -> ActivityHourInspection? {
        guard !hours.isEmpty else { return nil }
        let hour = min(23, max(0, Int(raw.rounded())))
        return hours[hour]
    }

    public func period(at index: Int) -> ActivityPeriodInspection? {
        guard periods.indices.contains(index) else { return nil }
        return periods[index]
    }

    public func period(nearestLabel hint: String?) -> ActivityPeriodInspection? {
        guard let hint, !periods.isEmpty else { return nil }
        return periods.first(where: { $0.label == hint })
    }

    private static func contributionLines(
        _ contributions: [ActivitySeatContribution],
        accountLabels: [SeatID: String]
    ) -> [String] {
        guard !contributions.isEmpty, !accountLabels.isEmpty else { return [] }
        return contributions
            .filter { $0.requestCount > 0 }
            .sorted { $0.seatID.rawValue < $1.seatID.rawValue }
            .compactMap { row in
                guard let label = accountLabels[row.seatID] else { return nil }
                return "\(label): \(row.requestCount) requests"
            }
    }

    private static func minOptional(_ a: Int64?, _ b: Int64?) -> Int64? {
        switch (a, b) {
        case let (x?, y?): return min(x, y)
        case let (x?, nil): return x
        case let (nil, y?): return y
        case (nil, nil): return nil
        }
    }

    private static func maxOptional(_ a: Int64?, _ b: Int64?) -> Int64? {
        switch (a, b) {
        case let (x?, y?): return max(x, y)
        case let (x?, nil): return x
        case let (nil, y?): return y
        case (nil, nil): return nil
        }
    }
}
