import Foundation

/// Calendar year-month in a concrete time zone (UI months). Not a UTC day key.
public struct YearMonth: Sendable, Equatable, Hashable, Comparable, Codable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month))
        self.year = year
        self.month = month
    }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.month < rhs.month
    }

    public static func current(now: Date = Date(), timeZone: TimeZone = .current) -> YearMonth {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month], from: now)
        return YearMonth(year: parts.year!, month: parts.month!)
    }

    public func addingMonths(_ delta: Int) -> YearMonth {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let date = calendar.date(from: components)!
        let shifted = calendar.date(byAdding: .month, value: delta, to: date)!
        let parts = calendar.dateComponents([.year, .month], from: shifted)
        return YearMonth(year: parts.year!, month: parts.month!)
    }

    public var previous: YearMonth { addingMonths(-1) }
    public var next: YearMonth { addingMonths(1) }

    /// Half-open local-month bounds as UTC epoch milliseconds: `[start, nextMonthStart)`.
    public func utcHalfOpenIntervalMs(timeZone: TimeZone) -> (startMs: Int64, endExclusiveMs: Int64) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let start = calendar.date(from: components)!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return (
            Int64(start.timeIntervalSince1970 * 1000.0),
            Int64(end.timeIntervalSince1970 * 1000.0)
        )
    }

    /// UTC day keys overlapping the local month request interval (inclusive chart fill).
    public func overlappingUTCDays(timeZone: TimeZone) -> (start: UsageDayKey, end: UsageDayKey) {
        let bounds = utcHalfOpenIntervalMs(timeZone: timeZone)
        let start = UsageDayKey.utcDay(containing: Date(timeIntervalSince1970: TimeInterval(bounds.startMs) / 1000.0))
        let endInstant = Date(timeIntervalSince1970: TimeInterval(bounds.endExclusiveMs - 1) / 1000.0)
        let end = UsageDayKey.utcDay(containing: endInstant)
        return (start, end)
    }

    public func localizedTitle(
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let date = calendar.date(from: components)!
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }
}
