import CursorBarDomain
import Foundation

extension UsageSeriesRefresher {
    func fetchAll(
        credentials: [SeatCredential],
        range: UsageRange,
        chartStart: UsageDayKey,
        chartEnd: UsageDayKey,
        seatStarts: [SeatID: UsageDayKey],
        timeZone: TimeZone,
        token: UInt64
    ) async -> (
        outcomes: [(SeatID, SeatSeriesOutcome)],
        chunkCount: Int,
        missingMonthCount: Int
    ) {
        await withTaskGroup(of: (SeatID, SeatSeriesOutcome, Int, Int).self) { group in
            for credential in credentials {
                group.addTask {
                    let result = await self.fetchOne(
                        credential: credential,
                        range: range,
                        chartStart: chartStart,
                        chartEnd: chartEnd,
                        accountStart: seatStarts[credential.seatID],
                        timeZone: timeZone,
                        token: token
                    )
                    return (
                        result.outcome.0,
                        result.outcome.1,
                        result.chunkCount,
                        result.missingMonthCount
                    )
                }
            }
            var collected: [(SeatID, SeatSeriesOutcome)] = []
            var chunks = 0
            var missing = 0
            for await item in group {
                collected.append((item.0, item.1))
                chunks += item.2
                missing += item.3
            }
            return (collected, chunks, missing)
        }
    }

    func fetchOne(
        credential: SeatCredential,
        range: UsageRange,
        chartStart: UsageDayKey,
        chartEnd: UsageDayKey,
        accountStart: UsageDayKey?,
        timeZone: TimeZone,
        token: UInt64
    ) async -> (
        outcome: (SeatID, SeatSeriesOutcome),
        chunkCount: Int,
        missingMonthCount: Int
    ) {
        switch range {
        case .month(let month):
            let result = await fetchMonth(
                credential: credential,
                month: month,
                chartStart: chartStart,
                chartEnd: chartEnd,
                accountStart: accountStart,
                timeZone: timeZone,
                token: token
            )
            return (result.outcome, result.chunkCount, 0)
        case .allTime(_, let end):
            let fetchStart = chartStart
            guard fetchStart <= end else {
                let empty = UsageSeriesAggregator.seatSeries(
                    seatID: credential.seatID,
                    rows: [],
                    rangeStart: chartStart,
                    rangeEnd: chartEnd,
                    accountStart: nil
                )
                return ((credential.seatID, .refreshed(empty)), 0, 0)
            }
            let epoch = bindingEpochBySeat[credential.seatID] ?? 0
            let loaded = await UsageAllTimeSeriesLoader.fetch(
                credential: credential,
                start: fetchStart,
                end: end,
                chartStart: chartStart,
                chartEnd: chartEnd,
                accountStart: nil,
                timeZone: timeZone,
                client: client,
                gate: chunkGate,
                chunkCache: chunkCache
            ) { result in
                await self.publishSeriesProgress(
                    outcome: result.outcome,
                    token: token
                )
            }
            guard commitSeriesCache(
                seatID: credential.seatID,
                token: token,
                epoch: epoch,
                writes: loaded.cacheWrites,
                networkIncrements: loaded.networkIncrements
            ) else {
                return ((credential.seatID, .failed), loaded.chunkCount, loaded.missingMonthCount)
            }
            return (loaded.outcome, loaded.chunkCount, loaded.missingMonthCount)
        }
    }

    func fetchMonth(
        credential: SeatCredential,
        month: YearMonth,
        chartStart: UsageDayKey,
        chartEnd: UsageDayKey,
        accountStart: UsageDayKey?,
        timeZone: TimeZone,
        token: UInt64
    ) async -> (outcome: (SeatID, SeatSeriesOutcome), chunkCount: Int) {
        let key = UsageSeriesChunkKey(seatID: credential.seatID, month: month)
        let currentMonth = YearMonth.current(timeZone: timeZone)
        if month < currentMonth, let cached = chunkCache[key] {
            let clipped = UsageAllTimeSeriesLoader.clipCached(
                cached,
                chartStart: chartStart,
                chartEnd: chartEnd,
                accountStart: accountStart
            )
            return ((credential.seatID, .refreshed(clipped)), 0)
        }
        let epoch = bindingEpochBySeat[credential.seatID] ?? 0
        let bounds = month.utcHalfOpenIntervalMs(timeZone: timeZone)
        do {
            let rows = try await client.getDailySpendByCategory(
                access: credential.access,
                periodStartMs: bounds.startMs,
                periodEndMs: bounds.endExclusiveMs
            )
            let series = UsageSeriesAggregator.seatSeries(
                seatID: credential.seatID,
                rows: rows,
                rangeStart: chartStart,
                rangeEnd: chartEnd,
                accountStart: accountStart
            )
            let monthDays = month.overlappingUTCDays(timeZone: timeZone)
            let staged = UsageSeriesAggregator.seatSeries(
                seatID: credential.seatID,
                rows: rows,
                rangeStart: monthDays.start,
                rangeEnd: monthDays.end,
                accountStart: accountStart
            )
            guard commitSeriesCache(
                seatID: credential.seatID,
                token: token,
                epoch: epoch,
                writes: [key: staged],
                networkIncrements: [key]
            ) else {
                return ((credential.seatID, .failed), 1)
            }
            return ((credential.seatID, .refreshed(series)), 1)
        } catch {
            return ((credential.seatID, .failed), 1)
        }
    }
}
