import Foundation

/// Local-calendar day for work-behavior bucketing. Distinct from UTC `UsageDayKey` used by the graph.
public struct ActivityDayKey: Sendable, Equatable, Hashable, Comparable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: ActivityDayKey, rhs: ActivityDayKey) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    public static func localDay(containing date: Date, timeZone: TimeZone) -> ActivityDayKey {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return ActivityDayKey(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public static func localDay(timestampMs: Int64, timeZone: TimeZone) -> ActivityDayKey {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0)
        return localDay(containing: date, timeZone: timeZone)
    }

    public var isoDate: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
