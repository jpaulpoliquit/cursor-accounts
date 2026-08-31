import Foundation

/// Month-over-month comparison and gated prose for ActivityInsights.
public enum ActivityMonthOverMonth {
    public static func compare(
        current: ActivityInsights,
        previousSeats: [ActivityAnalyzer.SeatEvents],
        previousRequestedSeatCount: Int,
        range: UsageRange,
        timeZone: TimeZone,
        idleGap: IdleGapPolicy,
        now: Date
    ) -> MonthOverMonthComparison? {
        guard case .month(let month) = range else { return nil }
        let previousRange = UsageRange.month(month.previous)
        let previous = ActivityAnalyzer.analyze(
            seats: previousSeats,
            scope: current.scope,
            range: previousRange,
            timeZone: timeZone,
            idleGap: idleGap,
            now: now,
            previousMonthSeats: nil,
            requestedSeatCount: previousRequestedSeatCount
        )
        let currentPartial = current.coverage.isPartialMonth
        let currentLabel = currentPartial
            ? "\(month.localizedTitle(timeZone: timeZone)) so far"
            : month.localizedTitle(timeZone: timeZone)
        let previousLabel = month.previous.localizedTitle(timeZone: timeZone)

        let allowsProse = !currentPartial
            && !current.coverage.hasPartialSeatCoverage
            && !previous.coverage.hasPartialSeatCoverage
            && current.activeDayCount >= 5
            && previous.activeDayCount >= 5
            && current.totalRequests >= 50
            && previous.totalRequests >= 50
            && !current.coverage.truncated
            && !previous.coverage.truncated

        return MonthOverMonthComparison(
            currentLabel: currentLabel,
            previousLabel: previousLabel,
            currentIsPartial: currentPartial,
            currentRequests: current.totalRequests,
            previousRequests: previous.totalRequests,
            currentActiveDays: current.activeDayCount,
            previousActiveDays: previous.activeDayCount,
            currentMedianRequestsPerDay: medianDouble(current.days.map { Double($0.requestCount) }),
            previousMedianRequestsPerDay: medianDouble(previous.days.map { Double($0.requestCount) }),
            currentMedianSpanMs: current.medianDailySpanMs,
            previousMedianSpanMs: previous.medianDailySpanMs,
            currentMedianEstimatedActiveMs: current.medianEstimatedActiveMs,
            previousMedianEstimatedActiveMs: previous.medianEstimatedActiveMs,
            currentEveningShare: eveningShare(current.hourOfDayCounts),
            previousEveningShare: eveningShare(previous.hourOfDayCounts),
            currentWeekendShare: weekendShare(current.dayOfWeekCounts),
            previousWeekendShare: weekendShare(previous.dayOfWeekCounts),
            allowsProse: allowsProse,
            proseLines: allowsProse
                ? proseLines(
                    current: current,
                    previous: previous,
                    currentLabel: currentLabel,
                    previousLabel: previousLabel
                )
                : []
        )
    }

    public static func attaching(
        _ insights: ActivityInsights,
        comparison: MonthOverMonthComparison?
    ) -> ActivityInsights {
        ActivityInsights(
            scope: insights.scope,
            range: insights.range,
            timeZoneIdentifier: insights.timeZoneIdentifier,
            idleGap: insights.idleGap,
            hourOfDayCounts: insights.hourOfDayCounts,
            hourOfDayTokens: insights.hourOfDayTokens,
            dayOfWeekCounts: insights.dayOfWeekCounts,
            days: insights.days,
            totalRequests: insights.totalRequests,
            totalTokens: insights.totalTokens,
            money: insights.money,
            activeDayCount: insights.activeDayCount,
            medianDailySpanMs: insights.medianDailySpanMs,
            medianEstimatedActiveMs: insights.medianEstimatedActiveMs,
            coverage: insights.coverage,
            monthOverMonth: comparison,
            estimatedActiveIsPerSeatSum: insights.estimatedActiveIsPerSeatSum,
            modelCatalog: insights.modelCatalog
        )
    }

    private static func eveningShare(_ hours: [Int]) -> Double? {
        let total = hours.reduce(0, +)
        guard total > 0 else { return nil }
        let evening = hours[18...23].reduce(0, +)
        return Double(evening) / Double(total)
    }

    private static func weekendShare(_ dow: [Int]) -> Double? {
        let total = dow.reduce(0, +)
        guard total > 0 else { return nil }
        return Double(dow[5] + dow[6]) / Double(total)
    }

    private static func proseLines(
        current: ActivityInsights,
        previous: ActivityInsights,
        currentLabel: String,
        previousLabel: String
    ) -> [String] {
        var lines: [String] = []
        let reqDelta = current.totalRequests - previous.totalRequests
        let reqBase = max(previous.totalRequests, 1)
        let reqPct = Double(reqDelta) / Double(reqBase)
        if abs(reqDelta) >= 20, abs(reqPct) >= 0.15 {
            let direction = reqDelta > 0 ? "up" : "down"
            lines.append(
                "Requests \(direction) \(abs(reqDelta)) versus \(previousLabel) (\(currentLabel))."
            )
        }
        let dayDelta = current.activeDayCount - previous.activeDayCount
        if abs(dayDelta) >= 2 {
            let direction = dayDelta > 0 ? "more" : "fewer"
            lines.append("\(abs(dayDelta)) \(direction) active days than \(previousLabel).")
        }
        if let curE = eveningShare(current.hourOfDayCounts),
           let prevE = eveningShare(previous.hourOfDayCounts),
           abs(curE - prevE) >= 0.10
        {
            let direction = curE > prevE ? "higher" : "lower"
            lines.append("Evening share (6–11 PM) is \(direction) than \(previousLabel).")
        }
        if let curW = weekendShare(current.dayOfWeekCounts),
           let prevW = weekendShare(previous.dayOfWeekCounts),
           abs(curW - prevW) >= 0.10
        {
            let direction = curW > prevW ? "higher" : "lower"
            lines.append("Weekend share is \(direction) than \(previousLabel).")
        }
        return lines
    }

    private static func medianDouble(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
