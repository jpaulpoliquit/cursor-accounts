import CursorBarDomain
import Foundation

extension UsageSeriesRefresher {
    /// Commit staged chunk writes only while refresh generation and seat cache epoch remain current.
    @discardableResult
    func commitSeriesCache(
        seatID: SeatID,
        token: UInt64,
        epoch: UInt64,
        writes: [UsageSeriesChunkKey: SeatUsageSeries],
        networkIncrements: [UsageSeriesChunkKey]
    ) -> Bool {
        guard token == generation else { return false }
        guard epoch == (bindingEpochBySeat[seatID] ?? 0) else { return false }
        for (key, series) in writes {
            chunkCache[key] = series
        }
        for key in networkIncrements {
            networkFetchCounts[key, default: 0] += 1
        }
        return true
    }

    @discardableResult
    func commitWarmSeriesCache(
        seatID: SeatID,
        epoch: UInt64,
        warmToken: UInt64,
        writes: [UsageSeriesChunkKey: SeatUsageSeries],
        networkIncrements: [UsageSeriesChunkKey]
    ) -> Bool {
        guard warmToken == warmGenerationBySeat[seatID] else { return false }
        guard epoch == (bindingEpochBySeat[seatID] ?? 0) else { return false }
        for (key, series) in writes {
            chunkCache[key] = series
        }
        for key in networkIncrements {
            networkFetchCounts[key, default: 0] += 1
        }
        return true
    }

    func commit(
        fetched: [(SeatID, SeatSeriesOutcome)],
        requested: Int,
        scope: UsageScope,
        rangeStart: UsageDayKey,
        rangeEnd: UsageDayKey,
        chunkCount: Int,
        missingMonthCount: Int,
        maxInFlight: Int
    ) -> Commit {
        var outcomes: [SeatID: SeatSeriesOutcome] = [:]
        var successful: [SeatUsageSeries] = []
        for (seatID, outcome) in fetched {
            outcomes[seatID] = outcome
            if case .refreshed(let series) = outcome {
                lastKnownBySeat[seatID] = series
                successful.append(series)
            }
        }
        let series = UsageSeriesAggregator.aggregate(
            successful: successful,
            requestedAccountCount: requested,
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            missingMonthCount: missingMonthCount
        )
        let report = Report(
            series: series,
            outcomes: outcomes,
            chunkCount: chunkCount,
            maxInFlight: maxInFlight
        )
        if successful.isEmpty {
            if let previous = lastSeries, previous.scope == scope,
               previous.rangeStart == rangeStart, previous.rangeEnd == rangeEnd
            {
                return .applied(
                    Report(
                        series: previous,
                        outcomes: outcomes,
                        chunkCount: chunkCount,
                        maxInFlight: maxInFlight
                    )
                )
            }
            if lastSeries == nil {
                lastSeries = series
            }
            return .applied(report)
        }
        lastSeries = series
        return .applied(report)
    }

    func publishSeriesProgress(
        outcome: (SeatID, SeatSeriesOutcome),
        token: UInt64
    ) async {
        guard token == generation, reportProgress != nil else { return }
        progressOutcomes[outcome.0] = outcome.1
        let maxInFlight = await chunkGate.maxObservedInFlight
        let commit = commit(
            fetched: progressOutcomes.map { ($0.key, $0.value) },
            requested: progressRequested,
            scope: progressScope,
            rangeStart: progressRangeStart,
            rangeEnd: progressRangeEnd,
            chunkCount: 0,
            missingMonthCount: 0,
            maxInFlight: maxInFlight
        )
        if case .applied(let report) = commit {
            let anySuccess = report.outcomes.values.contains {
                if case .refreshed = $0 { return true }
                return false
            }
            if anySuccess {
                reportProgress?(report)
            }
        }
    }
}
