import CursorBarDomain
import Foundation

extension UsageTokenSummaryRefresher {
    func fetchAllTimeChunked(
        credential: SeatCredential,
        start: UsageDayKey,
        end: UsageDayKey,
        timeZone: TimeZone,
        token: UInt64
    ) async -> (SeatID, SeatSummaryOutcome) {
        let months = UsageRangeChunks.recentMonths(
            from: start,
            through: end,
            timeZone: timeZone,
            limit: HistoryWarmBudget.seriesAllTime.maxMonths
        )
        let current = YearMonth.current(timeZone: timeZone)
        let client = self.client
        let epoch = bindingEpochBySeat[credential.seatID] ?? 0

        struct ChunkResult: Sendable {
            let index: Int
            let summary: SeatUsageTokenSummary?
            let month: YearMonth
        }

        func mergedOutcome(_ results: [ChunkResult]) -> (SeatID, SeatSummaryOutcome)? {
            var successful: [SeatUsageTokenSummary] = []
            var failedCount = 0
            var coveredStart: UsageDayKey?
            var coveredEnd: UsageDayKey?
            for result in results {
                let days = result.month.overlappingUTCDays(timeZone: timeZone)
                if let summary = result.summary {
                    successful.append(summary)
                    coveredStart = coveredStart.map { min($0, days.start) } ?? days.start
                    coveredEnd = coveredEnd.map { max($0, min(days.end, end)) } ?? min(days.end, end)
                } else {
                    failedCount += 1
                }
            }
            guard let merged = UsageTokenSummaryAggregator.mergeSeatChunks(successful) else {
                return nil
            }
            let pending = months.count - results.count
            let temporal = TemporalCoverage(
                requestedStart: start,
                requestedEnd: end,
                coveredStart: coveredStart,
                coveredEnd: coveredEnd,
                failedChunkCount: failedCount + pending
            )
            return (credential.seatID, .refreshed(merged, temporal))
        }

        if reportProgress != nil {
            var preview: [ChunkResult] = []
            for (index, month) in months.enumerated() {
                let key = CacheKey.month(credential.seatID, year: month.year, month: month.month)
                if month < current, let cached = cache[key] {
                    preview.append(ChunkResult(index: index, summary: cached, month: month))
                }
            }
            if let outcome = mergedOutcome(preview) {
                publishTokenProgress(outcome: outcome, token: token)
            }
        }

        var collected: [ChunkResult] = []
        await withTaskGroup(of: ChunkResult.self) { group in
            for (index, month) in months.enumerated() {
                let key = CacheKey.month(credential.seatID, year: month.year, month: month.month)
                let cached = (month < current) ? cache[key] : nil
                group.addTask {
                    if let cached {
                        return ChunkResult(index: index, summary: cached, month: month)
                    }
                    return await self.chunkGate.withPermit(seatID: credential.seatID) {
                        let bounds = month.utcHalfOpenIntervalMs(timeZone: timeZone)
                        do {
                            let summary = try await client.getAggregatedUsageEvents(
                                access: credential.access,
                                startDateMs: bounds.startMs,
                                endDateMs: bounds.endExclusiveMs,
                                seatID: credential.seatID
                            )
                            return ChunkResult(index: index, summary: summary, month: month)
                        } catch {
                            return ChunkResult(index: index, summary: nil, month: month)
                        }
                    }
                }
            }
            for await item in group {
                collected.append(item)
                if reportProgress != nil, let outcome = mergedOutcome(collected) {
                    publishTokenProgress(outcome: outcome, token: token)
                }
            }
        }

        var staged: [CacheKey: SeatUsageTokenSummary] = [:]
        for result in collected {
            if let summary = result.summary, result.month < current {
                let key = CacheKey.month(
                    credential.seatID,
                    year: result.month.year,
                    month: result.month.month
                )
                staged[key] = summary
            }
        }

        guard commitTokenCache(
            seatID: credential.seatID,
            token: token,
            epoch: epoch,
            writes: staged
        ) else {
            return (credential.seatID, .failed)
        }

        return mergedOutcome(collected) ?? (credential.seatID, .failed)
    }

    func publishTokenProgress(
        outcome: (SeatID, SeatSummaryOutcome),
        token: UInt64
    ) {
        guard token == generation, reportProgress != nil else { return }
        progressOutcomes[outcome.0] = outcome.1
        let commit = commit(
            fetched: progressOutcomes.map { ($0.key, $0.value) },
            requested: progressRequested,
            scope: progressScope,
            range: progressRange,
            now: progressNow
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

    /// Commit staged month summaries only while refresh generation and seat cache epoch remain current.
    @discardableResult
    func commitTokenCache(
        seatID: SeatID,
        token: UInt64,
        epoch: UInt64,
        writes: [CacheKey: SeatUsageTokenSummary]
    ) -> Bool {
        guard token == generation else { return false }
        guard epoch == (bindingEpochBySeat[seatID] ?? 0) else { return false }
        for (key, summary) in writes {
            cache[key] = summary
        }
        return true
    }

    @discardableResult
    func commitWarmTokenCache(
        seatID: SeatID,
        epoch: UInt64,
        warmToken: UInt64,
        writes: [CacheKey: SeatUsageTokenSummary],
        summary: SeatUsageTokenSummary
    ) -> Bool {
        guard warmToken == warmGenerationBySeat[seatID] else { return false }
        guard epoch == (bindingEpochBySeat[seatID] ?? 0) else { return false }
        for (key, value) in writes {
            cache[key] = value
        }
        _ = summary
        return true
    }

    func commit(
        fetched: [(SeatID, SeatSummaryOutcome)],
        requested: Int,
        scope: UsageScope,
        range: UsageRange,
        now: Date
    ) -> Commit {
        var outcomes: [SeatID: SeatSummaryOutcome] = [:]
        var successful: [SeatUsageTokenSummary] = []
        var temporalParts: [TemporalCoverage] = []

        for (seatID, outcome) in fetched {
            outcomes[seatID] = outcome
            if case .refreshed(let summary, let temporal) = outcome {
                successful.append(summary)
                if let temporal {
                    temporalParts.append(temporal)
                }
            }
        }

        let temporal = Self.mergeTemporal(temporalParts, range: range)
        let summary = UsageTokenSummaryAggregator.aggregate(
            successful: successful,
            requestedAccountCount: requested,
            scope: scope,
            range: range,
            temporalCoverage: temporal,
            fetchedAt: now
        )

        if successful.isEmpty {
            if let previous = lastSummary, previous.scope == scope, previous.range == range {
                return .applied(Report(summary: previous, outcomes: outcomes))
            }
            if lastSummary == nil {
                lastSummary = summary
            }
            return .applied(Report(summary: summary, outcomes: outcomes))
        }

        lastSummary = summary
        return .applied(Report(summary: summary, outcomes: outcomes))
    }

    static func mergeTemporal(
        _ parts: [TemporalCoverage],
        range: UsageRange
    ) -> TemporalCoverage? {
        guard case .allTime(let start, let end) = range else { return nil }
        guard !parts.isEmpty else {
            return TemporalCoverage(
                requestedStart: start,
                requestedEnd: end,
                coveredStart: nil,
                coveredEnd: nil,
                failedChunkCount: 1
            )
        }
        let coveredStarts = parts.compactMap(\.coveredStart)
        let coveredEnds = parts.compactMap(\.coveredEnd)
        return TemporalCoverage(
            requestedStart: start,
            requestedEnd: end,
            coveredStart: coveredStarts.min(),
            coveredEnd: coveredEnds.max(),
            failedChunkCount: parts.reduce(0) { $0 + $1.failedChunkCount }
        )
    }
}
