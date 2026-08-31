import Foundation

/// Selected chart timeline. Domain owns labels and UTC request arithmetic; views do not.
public enum UsageRange: Sendable, Equatable, Hashable, Codable {
    case month(YearMonth)
    /// Honest bound from account onboarding (`GetMe.createdAt`) through today UTC.
    /// Not claimed as earliest usage event.
    case allTime(start: UsageDayKey, end: UsageDayKey)

    public static func defaultMonth(now: Date = Date(), timeZone: TimeZone = .current) -> UsageRange {
        .month(.current(now: now, timeZone: timeZone))
    }

    public var isCurrentMonth: Bool {
        guard case .month(let month) = self else { return false }
        return month == .current()
    }

    public func title(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        switch self {
        case .month(let month):
            return month.localizedTitle(locale: locale, timeZone: timeZone)
        case .allTime:
            return "All time"
        }
    }

    public var canGoPrevious: Bool {
        switch self {
        case .month:
            return true
        case .allTime:
            return false
        }
    }

    public var canGoNext: Bool {
        switch self {
        case .month(let month):
            return month < .current()
        case .allTime:
            return false
        }
    }

    public func previous() -> UsageRange? {
        guard case .month(let month) = self else { return nil }
        return .month(month.previous)
    }

    public func next(now: Date = Date(), timeZone: TimeZone = .current) -> UsageRange? {
        guard case .month(let month) = self else { return nil }
        let advanced = month.next
        guard advanced <= YearMonth.current(now: now, timeZone: timeZone) else { return nil }
        return .month(advanced)
    }

    /// Half-open UTC request window for Dashboard GetDailySpendByCategory.
    public func utcRequestIntervalMs(timeZone: TimeZone = .current) -> (startMs: Int64, endExclusiveMs: Int64) {
        switch self {
        case .month(let month):
            return month.utcHalfOpenIntervalMs(timeZone: timeZone)
        case .allTime(let start, let end):
            return (start.utcMidnightMs, end.endOfDayExclusiveMs)
        }
    }

    /// Inclusive UTC day keys for chart fill / merge.
    public func chartUTCDays(timeZone: TimeZone = .current) -> (start: UsageDayKey, end: UsageDayKey) {
        switch self {
        case .month(let month):
            return month.overlappingUTCDays(timeZone: timeZone)
        case .allTime(let start, let end):
            return (start, end)
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .month(let month):
            return "Usage range \(month.localizedTitle())"
        case .allTime(let start, let end):
            return "Usage range all time from \(start.isoDate) through \(end.isoDate)"
        }
    }

    public var utcEdgeOverlapHint: String? {
        guard case .month = self else { return nil }
        return "Daily totals use UTC days. The first or last day may partly fall outside this local month."
    }

    /// All Time fetch/display window. Oldest months beyond `limit` are dropped.
    public func clippedToRecentMonths(_ limit: Int, timeZone: TimeZone) -> UsageRange {
        guard case .allTime(let start, let end) = self else { return self }
        guard start <= end else { return self }
        let months = UsageRangeChunks.recentMonths(
            from: start,
            through: end,
            timeZone: timeZone,
            limit: limit
        )
        guard let first = months.first, let last = months.last else { return self }
        let firstStart = first.overlappingUTCDays(timeZone: timeZone).start
        let lastEnd = last.overlappingUTCDays(timeZone: timeZone).end
        let clippedStart = start > firstStart ? start : firstStart
        let clippedEnd = end < lastEnd ? end : lastEnd
        return .allTime(start: clippedStart, end: clippedEnd)
    }
}

/// Month-sized chunks for bounded All Time fetches.
public enum UsageRangeChunks {
    public static func months(
        from start: UsageDayKey,
        through end: UsageDayKey,
        timeZone: TimeZone
    ) -> [YearMonth] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startDate = Date(timeIntervalSince1970: TimeInterval(start.utcMidnightMs) / 1000.0)
        let endDate = Date(timeIntervalSince1970: TimeInterval(end.utcMidnightMs) / 1000.0)
        let startParts = calendar.dateComponents([.year, .month], from: startDate)
        let endParts = calendar.dateComponents([.year, .month], from: endDate)
        var cursor = YearMonth(year: startParts.year!, month: startParts.month!)
        let last = YearMonth(year: endParts.year!, month: endParts.month!)
        var result: [YearMonth] = []
        while cursor <= last {
            result.append(cursor)
            cursor = cursor.next
        }
        return result
    }

    /// Newest `limit` months in chronological order. Older months are not fetched.
    public static func recentMonths(
        from start: UsageDayKey,
        through end: UsageDayKey,
        timeZone: TimeZone,
        limit: Int
    ) -> [YearMonth] {
        precondition(limit > 0)
        let all = months(from: start, through: end, timeZone: timeZone)
        if all.count <= limit { return all }
        return Array(all.suffix(limit))
    }
}
