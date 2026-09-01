import CursorBarDomain
import Foundation

enum UsageAllTimeSeriesLoader {
    struct Result: Sendable {
        let outcome: (SeatID, UsageSeriesRefresher.SeatSeriesOutcome)
        let chunkCount: Int
        let missingMonthCount: Int
        let cacheWrites: [UsageSeriesChunkKey: SeatUsageSeries]
        let networkIncrements: [UsageSeriesChunkKey]
    }

    struct ChunkOutcome: Sendable {
        let index: Int
        let rows: [DailySpendCategoryRow]?
        let fromCache: Bool
        let failed: Bool
    }

    static func fetch(
        credential: UsageSeriesRefresher.SeatCredential,
        start: UsageDayKey,
        end: UsageDayKey,
        chartStart: UsageDayKey,
        chartEnd: UsageDayKey,
        accountStart: UsageDayKey?,
        timeZone: TimeZone,
        client: DashboardClient,
        gate: FetchConcurrencyGate,
        chunkCache: [UsageSeriesChunkKey: SeatUsageSeries],
        onChunk: (@Sendable (Result) async -> Void)? = nil
    ) async -> Result {
        let months = UsageRangeChunks.recentMonths(
            from: start,
            through: end,
            timeZone: timeZone,
            limit: HistoryWarmBudget.seriesAllTime.maxMonths
        )
        let firstDays = months.first.map { $0.overlappingUTCDays(timeZone: timeZone) }
        let lastDays = months.last.map { $0.overlappingUTCDays(timeZone: timeZone) }
        let clippedChartStart = firstDays.map { max(chartStart, $0.start) } ?? chartStart
        let clippedChartEnd = lastDays.map { min(chartEnd, $0.end) } ?? chartEnd
        let currentMonth = YearMonth.current(timeZone: timeZone)

        if let onChunk {
            var preview: [Int: ChunkOutcome] = [:]
            for (index, month) in months.enumerated() {
                let key = UsageSeriesChunkKey(seatID: credential.seatID, month: month)
                if month < currentMonth, let cached = chunkCache[key] {
                    preview[index] = ChunkOutcome(
                        index: index,
                        rows: rowsFromCached(cached),
                        fromCache: true,
                        failed: false
                    )
                }
            }
            if !preview.isEmpty {
                await onChunk(
                    assemble(
                        credential: credential,
                        months: months,
                        known: preview,
                        clippedChartStart: clippedChartStart,
                        clippedChartEnd: clippedChartEnd,
                        accountStart: accountStart,
                        timeZone: timeZone
                    )
                )
            }
        }

        var known: [Int: ChunkOutcome] = [:]
        var last = assemble(
            credential: credential,
            months: months,
            known: known,
            clippedChartStart: clippedChartStart,
            clippedChartEnd: clippedChartEnd,
            accountStart: accountStart,
            timeZone: timeZone
        )
        await withTaskGroup(of: ChunkOutcome.self) { group in
            for (index, month) in months.enumerated() {
                let key = UsageSeriesChunkKey(seatID: credential.seatID, month: month)
                let cached = (month < currentMonth) ? chunkCache[key] : nil
                group.addTask {
                    if let cached {
                        return ChunkOutcome(
                            index: index,
                            rows: rowsFromCached(cached),
                            fromCache: true,
                            failed: false
                        )
                    }
                    return await gate.withPermit(seatID: credential.seatID) {
                        let bounds = month.utcHalfOpenIntervalMs(timeZone: timeZone)
                        do {
                            let rows = try await client.getDailySpendByCategory(
                                access: credential.access,
                                periodStartMs: bounds.startMs,
                                periodEndMs: bounds.endExclusiveMs
                            )
                            return ChunkOutcome(index: index, rows: rows, fromCache: false, failed: false)
                        } catch {
                            return ChunkOutcome(index: index, rows: nil, fromCache: false, failed: true)
                        }
                    }
                }
            }
            for await outcome in group {
                known[outcome.index] = outcome
                last = assemble(
                    credential: credential,
                    months: months,
                    known: known,
                    clippedChartStart: clippedChartStart,
                    clippedChartEnd: clippedChartEnd,
                    accountStart: accountStart,
                    timeZone: timeZone
                )
                if let onChunk {
                    await onChunk(last)
                }
            }
        }
        return last
    }

    static func clipCached(
        _ cached: SeatUsageSeries,
        chartStart: UsageDayKey,
        chartEnd: UsageDayKey,
        accountStart: UsageDayKey?
    ) -> SeatUsageSeries {
        let points = UsageDayKey.days(from: chartStart, through: chartEnd).map { day -> UsagePoint in
            if let accountStart, day < accountStart {
                return UsagePoint(
                    day: day,
                    tokens: 0,
                    spendCents: cached.costAvailable ? 0 : nil,
                    coverage: .complete,
                    contributions: [
                        DayAccountContribution(
                            seatID: cached.seatID,
                            tokens: 0,
                            spendCents: cached.costAvailable ? 0 : nil
                        ),
                    ]
                )
            }
            if let point = cached.points.first(where: { $0.day == day }) {
                return point
            }
            return UsagePoint(
                day: day,
                tokens: 0,
                spendCents: cached.costAvailable ? 0 : nil,
                coverage: .complete,
                contributions: [
                    DayAccountContribution(
                        seatID: cached.seatID,
                        tokens: 0,
                        spendCents: cached.costAvailable ? 0 : nil
                    ),
                ]
            )
        }
        return SeatUsageSeries(
            seatID: cached.seatID,
            rangeStart: chartStart,
            rangeEnd: chartEnd,
            points: points,
            costAvailable: cached.costAvailable
        )
    }

    private static func assemble(
        credential: UsageSeriesRefresher.SeatCredential,
        months: [YearMonth],
        known: [Int: ChunkOutcome],
        clippedChartStart: UsageDayKey,
        clippedChartEnd: UsageDayKey,
        accountStart: UsageDayKey?,
        timeZone: TimeZone
    ) -> Result {
        var mergedRows: [DailySpendCategoryRow] = []
        var uncoveredDays = Set<UsageDayKey>()
        var networkChunks = 0
        var missingMonths = 0
        var cacheWrites: [UsageSeriesChunkKey: SeatUsageSeries] = [:]
        var networkIncrements: [UsageSeriesChunkKey] = []

        for (index, month) in months.enumerated() {
            let monthDays = month.overlappingUTCDays(timeZone: timeZone)
            let dayKeys = UsageDayKey.days(from: monthDays.start, through: monthDays.end)
            guard let outcome = known[index] else {
                for day in dayKeys where day >= clippedChartStart && day <= clippedChartEnd {
                    uncoveredDays.insert(day)
                }
                continue
            }
            if outcome.failed {
                missingMonths += 1
                networkChunks += 1
                for day in dayKeys where day >= clippedChartStart && day <= clippedChartEnd {
                    uncoveredDays.insert(day)
                }
                continue
            }
            guard let rows = outcome.rows else { continue }
            mergedRows.append(contentsOf: rows)
            if !outcome.fromCache {
                networkChunks += 1
                let key = UsageSeriesChunkKey(seatID: credential.seatID, month: month)
                let series = UsageSeriesAggregator.seatSeries(
                    seatID: credential.seatID,
                    rows: rows,
                    rangeStart: monthDays.start,
                    rangeEnd: monthDays.end,
                    accountStart: accountStart
                )
                cacheWrites[key] = series
                networkIncrements.append(key)
            }
        }

        if missingMonths == months.count, !months.isEmpty, known.count == months.count {
            return Result(
                outcome: (credential.seatID, .failed),
                chunkCount: networkChunks,
                missingMonthCount: missingMonths,
                cacheWrites: cacheWrites,
                networkIncrements: networkIncrements
            )
        }

        let series = UsageSeriesAggregator.seatSeries(
            seatID: credential.seatID,
            rows: mergedRows,
            rangeStart: clippedChartStart,
            rangeEnd: clippedChartEnd,
            accountStart: accountStart,
            uncoveredDays: uncoveredDays
        )
        return Result(
            outcome: (credential.seatID, .refreshed(series)),
            chunkCount: networkChunks,
            missingMonthCount: missingMonths,
            cacheWrites: cacheWrites,
            networkIncrements: networkIncrements
        )
    }

    private static func rowsFromCached(_ cached: SeatUsageSeries) -> [DailySpendCategoryRow] {
        cached.points.compactMap { point -> DailySpendCategoryRow? in
            guard point.coverage != .missing else { return nil }
            return DailySpendCategoryRow(
                day: point.day,
                category: point.tokens > 0 || point.spendCents != nil ? "cached" : "cached-zero",
                spendCents: point.spendCents,
                totalTokens: point.tokens
            )
        }
    }
}
