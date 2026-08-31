import Foundation

/// Pure daily series math. Tokens and optional spend cents only.
public enum UsageSeriesAggregator {
    /// Sum category rows into filled UTC days. Successful missing day → explicit zero.
    /// Days in `uncoveredDays` are transport gaps (not zero). Days before `accountStart` are explicit zero.
    public static func seatSeries(
        seatID: SeatID,
        rows: [DailySpendCategoryRow],
        rangeStart: UsageDayKey,
        rangeEnd: UsageDayKey,
        accountStart: UsageDayKey? = nil,
        uncoveredDays: Set<UsageDayKey> = []
    ) -> SeatUsageSeries {
        var tokensByDay: [UsageDayKey: Int64] = [:]
        var spendByDay: [UsageDayKey: Int32] = [:]
        var spendSeen: Set<UsageDayKey> = []
        var anySpend = false

        for row in rows {
            tokensByDay[row.day, default: 0] += row.totalTokens
            if let cents = row.spendCents {
                anySpend = true
                spendByDay[row.day, default: 0] += cents
                spendSeen.insert(row.day)
            }
        }

        let days = UsageDayKey.days(from: rangeStart, through: rangeEnd)
        let points = days.map { day -> UsagePoint in
            if uncoveredDays.contains(day) {
                return UsagePoint(
                    day: day,
                    tokens: 0,
                    spendCents: nil,
                    coverage: .missing,
                    contributions: []
                )
            }
            if let accountStart, day < accountStart {
                let spend: Int32? = anySpend ? 0 : nil
                return UsagePoint(
                    day: day,
                    tokens: 0,
                    spendCents: spend,
                    coverage: .complete,
                    contributions: [
                        DayAccountContribution(seatID: seatID, tokens: 0, spendCents: spend),
                    ]
                )
            }
            let tokens = tokensByDay[day] ?? 0
            let spend: Int32? = anySpend ? (spendSeen.contains(day) ? spendByDay[day] : 0) : nil
            return UsagePoint(
                day: day,
                tokens: tokens,
                spendCents: spend,
                coverage: .complete,
                contributions: [
                    DayAccountContribution(seatID: seatID, tokens: tokens, spendCents: spend),
                ]
            )
        }
        return SeatUsageSeries(
            seatID: seatID,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            points: points,
            costAvailable: anySpend
        )
    }

    /// Aggregate successful seats. Failed seats are excluded and marked partial. Never zero-fill failures.
    public static func aggregate(
        successful: [SeatUsageSeries],
        requestedAccountCount: Int,
        scope: UsageScope,
        rangeStart: UsageDayKey,
        rangeEnd: UsageDayKey,
        missingMonthCount: Int = 0
    ) -> UsageSeries {
        let coverage = PartialCoverage(
            includedAccountCount: successful.count,
            requestedAccountCount: requestedAccountCount
        )
        let costAvailable = successful.contains(where: \.costAvailable)
        let days = UsageDayKey.days(from: rangeStart, through: rangeEnd)

        if successful.isEmpty {
            let points = days.map {
                UsagePoint(day: $0, tokens: 0, spendCents: nil, coverage: .missing)
            }
            return UsageSeries(
                scope: scope,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                points: points,
                coverage: coverage,
                costAvailable: false,
                missingMonthCount: missingMonthCount
            )
        }

        let pointsBySeat: [SeatID: [UsageDayKey: UsagePoint]] = {
            var map: [SeatID: [UsageDayKey: UsagePoint]] = [:]
            for series in successful {
                var dayMap: [UsageDayKey: UsagePoint] = [:]
                for point in series.points {
                    dayMap[point.day] = point
                }
                map[series.seatID] = dayMap
            }
            return map
        }()

        let points = days.map { day -> UsagePoint in
            var tokens: Int64 = 0
            var spendSum: Int32 = 0
            var spendPresent = false
            var contributions: [DayAccountContribution] = []
            var measuredSeats = 0
            var missingSeats = 0

            for series in successful {
                guard let point = pointsBySeat[series.seatID]?[day] else {
                    missingSeats += 1
                    continue
                }
                switch point.coverage {
                case .missing:
                    missingSeats += 1
                case .complete, .partial:
                    measuredSeats += 1
                    tokens += point.tokens
                    if let cents = point.spendCents {
                        spendSum += cents
                        spendPresent = true
                    }
                    if point.contributions.isEmpty {
                        contributions.append(
                            DayAccountContribution(
                                seatID: series.seatID,
                                tokens: point.tokens,
                                spendCents: point.spendCents
                            )
                        )
                    } else {
                        contributions.append(contentsOf: point.contributions)
                    }
                }
            }

            let pointCoverage: PointCoverage = {
                if measuredSeats == 0 { return .missing }
                if missingSeats > 0 || coverage.isPartial { return .partial }
                return .complete
            }()
            let spend: Int32? = costAvailable ? (spendPresent ? spendSum : 0) : nil
            return UsagePoint(
                day: day,
                tokens: tokens,
                spendCents: spend,
                coverage: pointCoverage,
                contributions: contributions
            )
        }

        return UsageSeries(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            points: points,
            coverage: coverage,
            costAvailable: costAvailable,
            missingMonthCount: missingMonthCount
        )
    }

    /// Chart range for a single account: billing cycle start through min(cycle end day, today UTC).
    public static func individualRange(
        cycle: BillingCycleBounds,
        today: UsageDayKey
    ) -> (start: UsageDayKey, end: UsageDayKey) {
        let start = cycle.startDay
        let cycleEnd = cycle.endDay
        let end = min(cycleEnd, today)
        if end < start {
            return (start, start)
        }
        return (start, end)
    }

    /// All Accounts alignment window: last 30 UTC days ending today.
    public static func allAccountsRange(today: UsageDayKey) -> (start: UsageDayKey, end: UsageDayKey) {
        UsageDayKey.lastUTCDays(count: 30, ending: today)
    }
}
