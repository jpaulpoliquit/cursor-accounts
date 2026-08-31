import Foundation

/// Privacy-safe per-seat slice inside an All Accounts day bar.
public struct ActivitySeatContribution: Sendable, Equatable, Hashable, Codable {
    public let seatID: SeatID
    public let requestCount: Int
    public let tokens: Int64

    public init(seatID: SeatID, requestCount: Int, tokens: Int64) {
        self.seatID = seatID
        self.requestCount = requestCount
        self.tokens = tokens
    }
}

/// Per local-day activity metrics.
public struct DayActivity: Sendable, Equatable, Hashable, Codable {
    public let day: ActivityDayKey
    public let requestCount: Int
    public let tokens: Int64
    /// Wall time from first to last request that day. Not active work time.
    public let spanMs: Int64
    /// Sum of consecutive gaps capped by idle policy. Estimated, not exact agent runtime.
    public let estimatedActiveMs: Int64
    public let firstRequestMs: Int64?
    public let lastRequestMs: Int64?
    public let contributions: [ActivitySeatContribution]

    public init(
        day: ActivityDayKey,
        requestCount: Int,
        tokens: Int64,
        spanMs: Int64,
        estimatedActiveMs: Int64,
        firstRequestMs: Int64? = nil,
        lastRequestMs: Int64? = nil,
        contributions: [ActivitySeatContribution] = []
    ) {
        self.day = day
        self.requestCount = requestCount
        self.tokens = tokens
        self.spanMs = spanMs
        self.estimatedActiveMs = estimatedActiveMs
        self.firstRequestMs = firstRequestMs
        self.lastRequestMs = lastRequestMs
        self.contributions = contributions
    }

    public var spanHours: Double { Double(spanMs) / 3_600_000.0 }
    public var estimatedActiveHours: Double { Double(estimatedActiveMs) / 3_600_000.0 }
}

/// Money totals for a selected Insights range. Distinct from seat-card current-period on-demand.
public struct ActivityMoneySummary: Sendable, Equatable, Hashable, Codable {
    public let onDemandChargedCents: Int64
    public let usageValueCents: Int64
    public let onDemandEventCount: Int
    public let usageValueEventCount: Int

    public init(
        onDemandChargedCents: Int64,
        usageValueCents: Int64,
        onDemandEventCount: Int,
        usageValueEventCount: Int
    ) {
        self.onDemandChargedCents = onDemandChargedCents
        self.usageValueCents = usageValueCents
        self.onDemandEventCount = onDemandEventCount
        self.usageValueEventCount = usageValueEventCount
    }
}

/// Fetch / merge coverage for honesty in the UI.
public struct ActivityCoverage: Sendable, Equatable, Hashable, Codable {
    public let requestedSeatCount: Int
    public let successfulSeatCount: Int
    public let truncated: Bool
    public let fetchedEventCount: Int
    public let reportedTotalEventCount: Int?
    public let isPartialMonth: Bool
    public let missingTokenUsageCount: Int

    public init(
        requestedSeatCount: Int,
        successfulSeatCount: Int,
        truncated: Bool,
        fetchedEventCount: Int,
        reportedTotalEventCount: Int?,
        isPartialMonth: Bool,
        missingTokenUsageCount: Int
    ) {
        self.requestedSeatCount = requestedSeatCount
        self.successfulSeatCount = successfulSeatCount
        self.truncated = truncated
        self.fetchedEventCount = fetchedEventCount
        self.reportedTotalEventCount = reportedTotalEventCount
        self.isPartialMonth = isPartialMonth
        self.missingTokenUsageCount = missingTokenUsageCount
    }

    public var hasPartialSeatCoverage: Bool {
        successfulSeatCount < requestedSeatCount
    }

    public var failedSeatCount: Int {
        max(0, requestedSeatCount - successfulSeatCount)
    }

    public var caption: String? {
        var parts: [String] = []
        if truncated {
            if let total = reportedTotalEventCount, total > fetchedEventCount {
                parts.append(
                    "Showing \(fetchedEventCount) of \(total) requests — history still loading"
                )
            } else {
                parts.append("Partial request history (\(fetchedEventCount) loaded)")
            }
        }
        if hasPartialSeatCoverage {
            parts.append("\(successfulSeatCount) of \(requestedSeatCount) accounts loaded")
            if failedSeatCount > 0 {
                parts.append("\(failedSeatCount) failed — try Refresh")
            }
        }
        if isPartialMonth {
            parts.append("Month so far")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Gated month-over-month numeric comparison. Prose only when `allowsProse`.
public struct MonthOverMonthComparison: Sendable, Equatable, Hashable, Codable {
    public let currentLabel: String
    public let previousLabel: String
    public let currentIsPartial: Bool
    public let currentRequests: Int
    public let previousRequests: Int
    public let currentActiveDays: Int
    public let previousActiveDays: Int
    public let currentMedianRequestsPerDay: Double?
    public let previousMedianRequestsPerDay: Double?
    public let currentMedianSpanMs: Int64?
    public let previousMedianSpanMs: Int64?
    public let currentMedianEstimatedActiveMs: Int64?
    public let previousMedianEstimatedActiveMs: Int64?
    public let currentEveningShare: Double?
    public let previousEveningShare: Double?
    public let currentWeekendShare: Double?
    public let previousWeekendShare: Double?
    public let allowsProse: Bool
    public let proseLines: [String]

    public init(
        currentLabel: String,
        previousLabel: String,
        currentIsPartial: Bool,
        currentRequests: Int,
        previousRequests: Int,
        currentActiveDays: Int,
        previousActiveDays: Int,
        currentMedianRequestsPerDay: Double?,
        previousMedianRequestsPerDay: Double?,
        currentMedianSpanMs: Int64?,
        previousMedianSpanMs: Int64?,
        currentMedianEstimatedActiveMs: Int64?,
        previousMedianEstimatedActiveMs: Int64?,
        currentEveningShare: Double?,
        previousEveningShare: Double?,
        currentWeekendShare: Double?,
        previousWeekendShare: Double?,
        allowsProse: Bool,
        proseLines: [String]
    ) {
        self.currentLabel = currentLabel
        self.previousLabel = previousLabel
        self.currentIsPartial = currentIsPartial
        self.currentRequests = currentRequests
        self.previousRequests = previousRequests
        self.currentActiveDays = currentActiveDays
        self.previousActiveDays = previousActiveDays
        self.currentMedianRequestsPerDay = currentMedianRequestsPerDay
        self.previousMedianRequestsPerDay = previousMedianRequestsPerDay
        self.currentMedianSpanMs = currentMedianSpanMs
        self.previousMedianSpanMs = previousMedianSpanMs
        self.currentMedianEstimatedActiveMs = currentMedianEstimatedActiveMs
        self.previousMedianEstimatedActiveMs = previousMedianEstimatedActiveMs
        self.currentEveningShare = currentEveningShare
        self.previousEveningShare = previousEveningShare
        self.currentWeekendShare = currentWeekendShare
        self.previousWeekendShare = previousWeekendShare
        self.allowsProse = allowsProse
        self.proseLines = proseLines
    }
}

/// Pure insights snapshot for one scope + range.
public struct ActivityInsights: Sendable, Equatable, Hashable, Codable {
    public let scope: UsageScope
    public let range: UsageRange
    public let timeZoneIdentifier: String
    public let idleGap: IdleGapPolicy
    public let hourOfDayCounts: [Int]
    public let hourOfDayTokens: [Int64]
    public let dayOfWeekCounts: [Int]
    public let days: [DayActivity]
    public let totalRequests: Int
    public let totalTokens: Int64
    public let money: ActivityMoneySummary
    public let activeDayCount: Int
    public let medianDailySpanMs: Int64?
    public let medianEstimatedActiveMs: Int64?
    public let coverage: ActivityCoverage
    public let monthOverMonth: MonthOverMonthComparison?
    /// When true, All Accounts estimated-active is the sum of per-seat estimates (may overlap in wall clock).
    public let estimatedActiveIsPerSeatSum: Bool
    public let modelCatalog: ModelPricingCatalog

    public init(
        scope: UsageScope,
        range: UsageRange,
        timeZoneIdentifier: String,
        idleGap: IdleGapPolicy,
        hourOfDayCounts: [Int],
        hourOfDayTokens: [Int64] = Array(repeating: 0, count: 24),
        dayOfWeekCounts: [Int],
        days: [DayActivity],
        totalRequests: Int,
        totalTokens: Int64,
        money: ActivityMoneySummary = ActivityMoneySummary(
            onDemandChargedCents: 0,
            usageValueCents: 0,
            onDemandEventCount: 0,
            usageValueEventCount: 0
        ),
        activeDayCount: Int,
        medianDailySpanMs: Int64?,
        medianEstimatedActiveMs: Int64?,
        coverage: ActivityCoverage,
        monthOverMonth: MonthOverMonthComparison?,
        estimatedActiveIsPerSeatSum: Bool,
        modelCatalog: ModelPricingCatalog = .empty
    ) {
        precondition(hourOfDayCounts.count == 24)
        precondition(hourOfDayTokens.count == 24)
        precondition(dayOfWeekCounts.count == 7)
        self.scope = scope
        self.range = range
        self.timeZoneIdentifier = timeZoneIdentifier
        self.idleGap = idleGap
        self.hourOfDayCounts = hourOfDayCounts
        self.hourOfDayTokens = hourOfDayTokens
        self.dayOfWeekCounts = dayOfWeekCounts
        self.days = days
        self.totalRequests = totalRequests
        self.totalTokens = totalTokens
        self.money = money
        self.activeDayCount = activeDayCount
        self.medianDailySpanMs = medianDailySpanMs
        self.medianEstimatedActiveMs = medianEstimatedActiveMs
        self.coverage = coverage
        self.monthOverMonth = monthOverMonth
        self.estimatedActiveIsPerSeatSum = estimatedActiveIsPerSeatSum
        self.modelCatalog = modelCatalog
    }

    public var peakHourRangeAccessibility: String {
        guard totalRequests > 0 else { return "No requests in this range" }
        let maxCount = hourOfDayCounts.max() ?? 0
        guard maxCount > 0 else { return "No requests in this range" }
        var start = 0
        while start < 24, hourOfDayCounts[start] != maxCount { start += 1 }
        var end = start
        while end + 1 < 24, hourOfDayCounts[end + 1] == maxCount { end += 1 }
        if start == end {
            return "Most requests around \(Self.clockLabel(start))"
        }
        return "Most requests between \(Self.clockLabel(start)) and \(Self.clockLabel(end))"
    }

    public var accessibilityDescriptor: String {
        var parts = [
            "Work insights",
            "\(totalRequests) requests",
            "\(activeDayCount) active days",
        ]
        if let span = medianDailySpanMs {
            parts.append("median daily span \(Self.durationAccessibility(span))")
        }
        if let active = medianEstimatedActiveMs {
            parts.append("median estimated agent-active time \(Self.durationAccessibility(active))")
        }
        parts.append(idleGap.accessibilityLabel)
        parts.append(peakHourRangeAccessibility)
        if let caption = coverage.caption {
            parts.append(caption)
        }
        if estimatedActiveIsPerSeatSum {
            parts.append("Estimated agent-active time sums each account separately")
        }
        return parts.joined(separator: ", ")
    }

    public static func clockLabel(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        if h == 0 { return "12 AM" }
        if h < 12 { return "\(h) AM" }
        if h == 12 { return "12 PM" }
        return "\(h - 12) PM"
    }

    public static func durationAccessibility(_ ms: Int64) -> String {
        let totalMinutes = max(0, ms) / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) minutes" }
        if minutes == 0 { return "\(hours) hours" }
        return "\(hours) hours \(minutes) minutes"
    }

    public static func durationCompact(_ ms: Int64) -> String {
        let totalMinutes = max(0, ms) / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    /// Tokens for the focused seat vs the collective snapshot. Either side can be missing.
    public func tokenHeadline(thisSeatID: SeatID?) -> (thisAccount: Int64?, allAccounts: Int64?) {
        let thisAccount: Int64?
        if let thisSeatID, let row = seatActivityTotals(seatID: thisSeatID) {
            thisAccount = row.tokens
        } else if case .account(let id) = scope, id == thisSeatID {
            thisAccount = totalTokens
        } else {
            thisAccount = nil
        }
        let allAccounts: Int64?
        switch scope {
        case .allAccounts:
            allAccounts = totalTokens
        case .account:
            allAccounts = nil
        }
        return (thisAccount, allAccounts)
    }

    /// Per-seat rollup from All Accounts day contributions. Empty when history has no seat slices.
    public func seatActivityTotals(seatID: SeatID) -> (tokens: Int64, requests: Int)? {
        var tokens: Int64 = 0
        var requests = 0
        var sawContribution = false
        for day in days {
            guard let row = day.contributions.first(where: { $0.seatID == seatID }) else { continue }
            sawContribution = true
            tokens += row.tokens
            requests += row.requestCount
        }
        guard sawContribution else { return nil }
        return (tokens, requests)
    }
}
