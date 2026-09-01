import Foundation

extension ActivityInsights {
    /// Last `dayCount` local days, inclusive of today.
    public func trailingDays(
        dayCount: Int,
        now: Date,
        timeZone: TimeZone
    ) -> [DayActivity] {
        guard dayCount > 0 else { return [] }
        let end = ActivityDayKey.localDay(containing: now, timeZone: timeZone)
        let start = end.adding(days: -(dayCount - 1), timeZone: timeZone)
        return days.filter { $0.day >= start && $0.day <= end }
    }

    public var totalAgentTimeMs: Int64 {
        days.reduce(0) { $0 + $1.estimatedActiveMs }
    }

    public func trailingAgentTimeMs(dayCount: Int = 30, now: Date, timeZone: TimeZone) -> Int64 {
        trailingDays(dayCount: dayCount, now: now, timeZone: timeZone)
            .reduce(0) { $0 + $1.estimatedActiveMs }
    }

    public func trailingSpanMs(dayCount: Int = 30, now: Date, timeZone: TimeZone) -> Int64 {
        trailingDays(dayCount: dayCount, now: now, timeZone: timeZone)
            .reduce(0) { $0 + $1.calendarSpanMs }
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
