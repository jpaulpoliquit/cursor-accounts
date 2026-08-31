import Foundation

/// Pure activity metrics from typed requests. No I/O.
public enum ActivityAnalyzer {
    public struct SeatEvents: Sendable, Equatable {
        public let seatID: SeatID
        public let requests: [ActivityRequest]
        public let truncated: Bool
        public let reportedTotal: Int?

        public init(seatID: SeatID, requests: [ActivityRequest], truncated: Bool, reportedTotal: Int?) {
            self.seatID = seatID
            self.requests = requests
            self.truncated = truncated
            self.reportedTotal = reportedTotal
        }
    }

    public static func analyze(
        seats: [SeatEvents],
        scope: UsageScope,
        range: UsageRange,
        timeZone: TimeZone,
        idleGap: IdleGapPolicy = .thirtyMinutes,
        now: Date = Date(),
        previousMonthSeats: [SeatEvents]? = nil,
        requestedSeatCount: Int = 1,
        previousRequestedSeatCount: Int? = nil
    ) -> ActivityInsights {
        let allRequests = seats.flatMap(\.requests)
        let baseCoverage = coverage(
            seats: seats,
            requestedSeatCount: requestedSeatCount,
            range: range,
            timeZone: timeZone,
            now: now
        )

        // All Accounts with multiple seats: sum per-seat span/active. Do not merge
        // timestamps across distinct accounts into one idle-gap session.
        let multiAccount: Bool = {
            if case .allAccounts = scope { return seats.count > 1 }
            return false
        }()

        let base: ActivityInsights
        if multiAccount {
            base = analyzeMultiAccount(
                seats: seats,
                allRequests: allRequests,
                scope: scope,
                range: range,
                timeZone: timeZone,
                idleGap: idleGap,
                now: now,
                requestedSeatCount: requestedSeatCount
            )
        } else {
            base = analyzeRequests(
                allRequests,
                scope: scope,
                range: range,
                timeZone: timeZone,
                idleGap: idleGap,
                now: now,
                coverageBase: baseCoverage,
                estimatedActiveIsPerSeatSum: false,
                monthOverMonth: nil
            )
        }

        let mom = previousMonthSeats.flatMap {
            ActivityMonthOverMonth.compare(
                current: base,
                previousSeats: $0,
                previousRequestedSeatCount: previousRequestedSeatCount ?? requestedSeatCount,
                range: range,
                timeZone: timeZone,
                idleGap: idleGap,
                now: now
            )
        }
        return ActivityMonthOverMonth.attaching(base, comparison: mom)
    }

    public static func analyzeRequests(
        _ requests: [ActivityRequest],
        scope: UsageScope,
        range: UsageRange,
        timeZone: TimeZone,
        idleGap: IdleGapPolicy = .thirtyMinutes,
        now: Date = Date(),
        coverageBase: ActivityCoverage,
        estimatedActiveIsPerSeatSum: Bool,
        monthOverMonth: MonthOverMonthComparison?
    ) -> ActivityInsights {
        var hour = Array(repeating: 0, count: 24)
        var hourTokens = Array(repeating: Int64(0), count: 24)
        var dow = Array(repeating: 0, count: 7)
        var missingTokens = 0
        var totalTokens: Int64 = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        for req in requests {
            let date = Date(timeIntervalSince1970: TimeInterval(req.timestampMs) / 1000.0)
            let h = calendar.component(.hour, from: date)
            hour[h] += 1
            hourTokens[h] += req.tokens?.total ?? 0
            dow[mondayIndexedWeekday(calendar.component(.weekday, from: date))] += 1
            if let tokens = req.tokens {
                totalTokens += tokens.total
            } else {
                missingTokens += 1
            }
        }

        let perDay = dayMetrics(requests, timeZone: timeZone, idleGap: idleGap)
        let days = perDay.keys.sorted().map { perDay[$0]! }
        let coverage = ActivityCoverage(
            requestedSeatCount: coverageBase.requestedSeatCount,
            successfulSeatCount: coverageBase.successfulSeatCount,
            truncated: coverageBase.truncated,
            fetchedEventCount: coverageBase.fetchedEventCount,
            reportedTotalEventCount: coverageBase.reportedTotalEventCount,
            isPartialMonth: coverageBase.isPartialMonth,
            missingTokenUsageCount: missingTokens
        )
        return ActivityInsights(
            scope: scope,
            range: range,
            timeZoneIdentifier: timeZone.identifier,
            idleGap: idleGap,
            hourOfDayCounts: hour,
            hourOfDayTokens: hourTokens,
            dayOfWeekCounts: dow,
            days: days,
            totalRequests: requests.count,
            totalTokens: totalTokens,
            money: moneySummary(requests),
            activeDayCount: days.count,
            medianDailySpanMs: median(days.map(\.spanMs)),
            medianEstimatedActiveMs: median(days.map(\.estimatedActiveMs)),
            coverage: coverage,
            monthOverMonth: monthOverMonth,
            estimatedActiveIsPerSeatSum: estimatedActiveIsPerSeatSum,
            modelCatalog: ActivityModelCatalog.build(requests: requests, timeZone: timeZone)
        )
    }

    /// Per-day span and gap-capped estimated active time.
    public static func dayMetrics(
        _ requests: [ActivityRequest],
        timeZone: TimeZone,
        idleGap: IdleGapPolicy
    ) -> [ActivityDayKey: DayActivity] {
        var grouped: [ActivityDayKey: [Int64]] = [:]
        var tokensByDay: [ActivityDayKey: Int64] = [:]
        for req in requests {
            let day = ActivityDayKey.localDay(timestampMs: req.timestampMs, timeZone: timeZone)
            grouped[day, default: []].append(req.timestampMs)
            tokensByDay[day, default: 0] += req.tokens?.total ?? 0
        }
        var result: [ActivityDayKey: DayActivity] = [:]
        for (day, stamps) in grouped {
            let sorted = stamps.sorted()
            let span: Int64
            let active: Int64
            if sorted.count <= 1 {
                span = 0
                active = 0
            } else {
                span = sorted.last! - sorted.first!
                var sum: Int64 = 0
                for index in 1..<sorted.count {
                    let delta = sorted[index] - sorted[index - 1]
                    sum += min(delta, idleGap.maxGapMs)
                }
                active = sum
            }
            result[day] = DayActivity(
                day: day,
                requestCount: sorted.count,
                tokens: tokensByDay[day] ?? 0,
                spanMs: span,
                estimatedActiveMs: active,
                firstRequestMs: sorted.first,
                lastRequestMs: sorted.last
            )
        }
        return result
    }

    public static func isPartialMonth(range: UsageRange, timeZone: TimeZone, now: Date) -> Bool {
        guard case .month(let month) = range else { return false }
        return month == YearMonth.current(now: now, timeZone: timeZone)
    }

    private static func analyzeMultiAccount(
        seats: [SeatEvents],
        allRequests: [ActivityRequest],
        scope: UsageScope,
        range: UsageRange,
        timeZone: TimeZone,
        idleGap: IdleGapPolicy,
        now: Date,
        requestedSeatCount: Int
    ) -> ActivityInsights {
        var hour = Array(repeating: 0, count: 24)
        var hourTokens = Array(repeating: Int64(0), count: 24)
        var dow = Array(repeating: 0, count: 7)
        var dayMap: [ActivityDayKey: DayActivity] = [:]
        var totalRequests = 0
        var totalTokens: Int64 = 0
        var missingTokens = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        for seat in seats {
            let per = dayMetrics(seat.requests, timeZone: timeZone, idleGap: idleGap)
            for req in seat.requests {
                let date = Date(timeIntervalSince1970: TimeInterval(req.timestampMs) / 1000.0)
                let h = calendar.component(.hour, from: date)
                hour[h] += 1
                hourTokens[h] += req.tokens?.total ?? 0
                dow[mondayIndexedWeekday(calendar.component(.weekday, from: date))] += 1
                totalRequests += 1
                if let tokens = req.tokens {
                    totalTokens += tokens.total
                } else {
                    missingTokens += 1
                }
            }
            for (day, metrics) in per {
                let seatSlice = ActivitySeatContribution(
                    seatID: seat.seatID,
                    requestCount: metrics.requestCount,
                    tokens: metrics.tokens
                )
                if let existing = dayMap[day] {
                    dayMap[day] = DayActivity(
                        day: day,
                        requestCount: existing.requestCount + metrics.requestCount,
                        tokens: existing.tokens + metrics.tokens,
                        spanMs: existing.spanMs + metrics.spanMs,
                        estimatedActiveMs: existing.estimatedActiveMs + metrics.estimatedActiveMs,
                        firstRequestMs: minOptional(existing.firstRequestMs, metrics.firstRequestMs),
                        lastRequestMs: maxOptional(existing.lastRequestMs, metrics.lastRequestMs),
                        contributions: existing.contributions + [seatSlice]
                    )
                } else {
                    dayMap[day] = DayActivity(
                        day: metrics.day,
                        requestCount: metrics.requestCount,
                        tokens: metrics.tokens,
                        spanMs: metrics.spanMs,
                        estimatedActiveMs: metrics.estimatedActiveMs,
                        firstRequestMs: metrics.firstRequestMs,
                        lastRequestMs: metrics.lastRequestMs,
                        contributions: [seatSlice]
                    )
                }
            }
        }

        let days = dayMap.keys.sorted().map { dayMap[$0]! }
        return ActivityInsights(
            scope: scope,
            range: range,
            timeZoneIdentifier: timeZone.identifier,
            idleGap: idleGap,
            hourOfDayCounts: hour,
            hourOfDayTokens: hourTokens,
            dayOfWeekCounts: dow,
            days: days,
            totalRequests: totalRequests,
            totalTokens: totalTokens,
            money: moneySummary(allRequests),
            activeDayCount: days.count,
            medianDailySpanMs: median(days.map(\.spanMs)),
            medianEstimatedActiveMs: median(days.map(\.estimatedActiveMs)),
            coverage: coverage(
                seats: seats,
                requestedSeatCount: requestedSeatCount,
                range: range,
                timeZone: timeZone,
                now: now,
                missingTokenUsageCount: missingTokens
            ),
            monthOverMonth: nil,
            estimatedActiveIsPerSeatSum: true,
            modelCatalog: ActivityModelCatalog.build(requests: allRequests, timeZone: timeZone)
        )
    }

    private static func moneySummary(_ requests: [ActivityRequest]) -> ActivityMoneySummary {
        var onDemand: Int64 = 0
        var usageValue: Int64 = 0
        var onDemandCount = 0
        var usageValueCount = 0
        for req in requests {
            if let cents = req.onDemandChargedCents {
                onDemand += cents
                onDemandCount += 1
            }
            if let cents = req.usageValueCents {
                usageValue += cents
                usageValueCount += 1
            }
        }
        return ActivityMoneySummary(
            onDemandChargedCents: onDemand,
            usageValueCents: usageValue,
            onDemandEventCount: onDemandCount,
            usageValueEventCount: usageValueCount
        )
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

    private static func coverage(
        seats: [SeatEvents],
        requestedSeatCount: Int,
        range: UsageRange,
        timeZone: TimeZone,
        now: Date,
        missingTokenUsageCount: Int = 0
    ) -> ActivityCoverage {
        let fetched = seats.reduce(0) { $0 + $1.requests.count }
        let reported = seats.compactMap(\.reportedTotal)
        // Successful seats are exactly those passed in; denominator is the requested batch size.
        let requested = max(requestedSeatCount, seats.count)
        return ActivityCoverage(
            requestedSeatCount: requested,
            successfulSeatCount: seats.count,
            truncated: seats.contains(where: \.truncated),
            fetchedEventCount: fetched,
            reportedTotalEventCount: reported.isEmpty ? nil : reported.reduce(0, +),
            isPartialMonth: isPartialMonth(range: range, timeZone: timeZone, now: now),
            missingTokenUsageCount: missingTokenUsageCount
        )
    }

    private static func mondayIndexedWeekday(_ calendarWeekday: Int) -> Int {
        (calendarWeekday + 5) % 7
    }

    private static func median(_ values: [Int64]) -> Int64? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
