import Foundation

/// Daily chart metric. Cost is only selectable when series carry spendCents.
public enum UsageMetric: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case tokens
    case costCents

    public var chartTitle: String {
        switch self {
        case .tokens: "Daily tokens"
        case .costCents: "Daily cost"
        }
    }

    public var accessibilityName: String {
        switch self {
        case .tokens: "tokens"
        case .costCents: "cost in cents"
        }
    }
}

/// Chart scope. All Accounts uses a shared UTC window; account uses that seat’s billing cycle.
public enum UsageScope: Sendable, Equatable, Hashable, Codable {
    case allAccounts
    case account(SeatID)
}

/// UTC calendar day key. Buckets align on UTC midnight, never local TZ.
public struct UsageDayKey: Sendable, Equatable, Hashable, Comparable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: UsageDayKey, rhs: UsageDayKey) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    public static func utcDay(containing date: Date) -> UsageDayKey {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return UsageDayKey(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public static func utcDay(midnightMs: Int64) -> UsageDayKey {
        utcDay(containing: Date(timeIntervalSince1970: TimeInterval(midnightMs) / 1000.0))
    }

    public var utcMidnightMs: Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let date = calendar.date(from: components)!
        return Int64(date.timeIntervalSince1970 * 1000.0)
    }

    public var endOfDayExclusiveMs: Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let start = calendar.date(from: components)!
        let next = calendar.date(byAdding: .day, value: 1, to: start)!
        return Int64(next.timeIntervalSince1970 * 1000.0)
    }

    public static func days(from start: UsageDayKey, through end: UsageDayKey) -> [UsageDayKey] {
        guard start <= end else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var cursor = start
        var result: [UsageDayKey] = []
        while cursor <= end {
            result.append(cursor)
            let ms = cursor.utcMidnightMs
            let next = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
            let advanced = calendar.date(byAdding: .day, value: 1, to: next)!
            cursor = utcDay(containing: advanced)
        }
        return result
    }

    /// Last `count` UTC days ending on `end` (inclusive).
    public static func lastUTCDays(count: Int, ending end: UsageDayKey) -> (start: UsageDayKey, end: UsageDayKey) {
        precondition(count > 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let endDate = Date(timeIntervalSince1970: TimeInterval(end.utcMidnightMs) / 1000.0)
        let startDate = calendar.date(byAdding: .day, value: -(count - 1), to: endDate)!
        return (utcDay(containing: startDate), end)
    }

    public var isoDate: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

public enum PointCoverage: String, Sendable, Equatable, Hashable, Codable {
    case complete
    case partial
    case missing
}

/// Per-seat daily contribution preserved through All Accounts aggregation.
public struct DayAccountContribution: Sendable, Equatable, Hashable, Codable {
    public let seatID: SeatID
    public let tokens: Int64
    public let spendCents: Int32?

    public init(seatID: SeatID, tokens: Int64, spendCents: Int32?) {
        self.seatID = seatID
        self.tokens = tokens
        self.spendCents = spendCents
    }
}

public struct UsagePoint: Sendable, Equatable, Hashable, Codable {
    public let day: UsageDayKey
    public let tokens: Int64
    public let spendCents: Int32?
    public let coverage: PointCoverage
    /// Present for All Accounts (and single-seat when useful). Sum of measured contributions equals `tokens`.
    public let contributions: [DayAccountContribution]

    public init(
        day: UsageDayKey,
        tokens: Int64,
        spendCents: Int32?,
        coverage: PointCoverage,
        contributions: [DayAccountContribution] = []
    ) {
        self.day = day
        self.tokens = tokens
        self.spendCents = spendCents
        self.coverage = coverage
        self.contributions = contributions
    }

    public func value(for metric: UsageMetric) -> Double {
        switch metric {
        case .tokens:
            return Double(tokens)
        case .costCents:
            return Double(spendCents ?? 0)
        }
    }

    /// Day has measured tokens or spend. Missing and explicit-zero pad days do not qualify.
    public var hasDisplayableUsage: Bool {
        guard coverage != .missing else { return false }
        if tokens > 0 { return true }
        if let spendCents, spendCents > 0 { return true }
        return false
    }
}

public struct PartialCoverage: Sendable, Equatable, Hashable, Codable {
    public let includedAccountCount: Int
    public let requestedAccountCount: Int

    public init(includedAccountCount: Int, requestedAccountCount: Int) {
        self.includedAccountCount = includedAccountCount
        self.requestedAccountCount = requestedAccountCount
    }

    public var isPartial: Bool {
        includedAccountCount < requestedAccountCount
    }

    public var caption: String? {
        guard isPartial, requestedAccountCount > 0 else { return nil }
        return "\(includedAccountCount) of \(requestedAccountCount) accounts"
    }
}

/// One seat’s filled daily series for a concrete UTC day range.
public struct SeatUsageSeries: Sendable, Equatable, Hashable, Codable {
    public let seatID: SeatID
    public let rangeStart: UsageDayKey
    public let rangeEnd: UsageDayKey
    public let points: [UsagePoint]
    public let costAvailable: Bool

    public init(
        seatID: SeatID,
        rangeStart: UsageDayKey,
        rangeEnd: UsageDayKey,
        points: [UsagePoint],
        costAvailable: Bool
    ) {
        self.seatID = seatID
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.points = points
        self.costAvailable = costAvailable
    }
}

/// Aggregated or single-seat chart series. Never stores percentages.
public struct UsageSeries: Sendable, Equatable, Hashable, Codable {
    public let scope: UsageScope
    public let rangeStart: UsageDayKey
    public let rangeEnd: UsageDayKey
    public let points: [UsagePoint]
    public let coverage: PartialCoverage
    public let costAvailable: Bool
    /// Failed transport months (not empty HTTP 200). Absent when fully retrieved.
    public let missingMonthCount: Int

    public init(
        scope: UsageScope,
        rangeStart: UsageDayKey,
        rangeEnd: UsageDayKey,
        points: [UsagePoint],
        coverage: PartialCoverage,
        costAvailable: Bool,
        missingMonthCount: Int = 0
    ) {
        self.scope = scope
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.points = points
        self.coverage = coverage
        self.costAvailable = costAvailable
        self.missingMonthCount = missingMonthCount
    }

    public var availableMetrics: [UsageMetric] {
        if costAvailable {
            return [.tokens, .costCents]
        }
        return [.tokens]
    }

    public var monthCoverageCaption: String? {
        guard missingMonthCount > 0 else { return nil }
        let unit = missingMonthCount == 1 ? "month" : "months"
        return "\(missingMonthCount) \(unit) unavailable"
    }

    public var firstDisplayableDay: UsageDayKey? {
        points.first(where: \.hasDisplayableUsage)?.day
    }

    /// Days Charts can plot. Pending All Time months are `.missing` and must not mount a Chart.
    public var plottablePoints: [UsagePoint] {
        points.filter { $0.coverage != .missing }
    }

    public var hasPlottablePoints: Bool {
        points.contains { $0.coverage != .missing }
    }

    /// All Time charts start at first real usage. Month ranges keep leading zeros.
    /// Does not change fetch or stored account-age bounds.
    public func forDisplay(in range: UsageRange) -> UsageSeries {
        switch range {
        case .month:
            return self
        case .allTime:
            return trimmingLeadingInactiveDays()
        }
    }

    /// Drops leading empty days. Internal zeros after first usage stay.
    public func trimmingLeadingInactiveDays() -> UsageSeries {
        guard let first = points.firstIndex(where: { $0.hasDisplayableUsage }) else {
            return self
        }
        if first == 0 { return self }
        let trimmed = Array(points[first...])
        guard let newStart = trimmed.first?.day else { return self }
        return UsageSeries(
            scope: scope,
            rangeStart: newStart,
            rangeEnd: rangeEnd,
            points: trimmed,
            coverage: coverage,
            costAvailable: costAvailable,
            missingMonthCount: missingMonthCount
        )
    }
}

/// Sparse category×day row from GetDailySpendByCategory after wire decode.
public struct DailySpendCategoryRow: Sendable, Equatable, Hashable {
    public let day: UsageDayKey
    public let category: String
    public let spendCents: Int32?
    public let totalTokens: Int64

    public init(day: UsageDayKey, category: String, spendCents: Int32?, totalTokens: Int64) {
        self.day = day
        self.category = category
        self.spendCents = spendCents
        self.totalTokens = totalTokens
    }
}

public struct BillingCycleBounds: Sendable, Equatable, Hashable {
    public let startMs: Int64
    public let endMs: Int64

    public init(startMs: Int64, endMs: Int64) {
        self.startMs = startMs
        self.endMs = endMs
    }

    public var startDay: UsageDayKey { UsageDayKey.utcDay(midnightMs: startMs) }
    public var endDay: UsageDayKey { UsageDayKey.utcDay(midnightMs: endMs) }
}

public enum UsageSeriesRefreshPhase: Sendable, Equatable {
    case idle
    case refreshing
    case settled
    case failed(message: String)
}

public enum UsageChartAccessibility {
    public static func descriptor(
        metric: UsageMetric,
        scopeLabel: String,
        rangeStart: UsageDayKey,
        rangeEnd: UsageDayKey,
        coverage: PartialCoverage,
        pointCount: Int
    ) -> String {
        var parts = [
            metric.chartTitle,
            "scope \(scopeLabel)",
            "from \(rangeStart.isoDate) through \(rangeEnd.isoDate)",
            "\(pointCount) daily points",
        ]
        if let caption = coverage.caption {
            parts.append("partial data \(caption)")
        } else {
            parts.append("complete coverage")
        }
        return parts.joined(separator: ", ")
    }
}

public enum UsageScopeLabels {
    public static func label(for scope: UsageScope, accountLabel: AccountLabel?) -> String {
        switch scope {
        case .allAccounts:
            return "All Accounts"
        case .account:
            return accountLabel?.text ?? "Account"
        }
    }
}
