import CursorBarDomain
import Foundation

extension UsageInsightsRefresher {
    func fetchSeats(
        _ credentials: [SeatCredential],
        range: UsageRange,
        timeZone: TimeZone,
        refreshGeneration: UInt64?,
        seatStarts: [SeatID: UsageDayKey] = [:],
        allTimeBudget: HistoryWarmBudget = .interactiveAllTime
    ) async -> [(SeatID, SeatOutcome)] {
        await withTaskGroup(of: (SeatID, SeatOutcome).self) { group in
            for credential in credentials {
                group.addTask {
                    await self.fetchOne(
                        credential: credential,
                        range: range,
                        timeZone: timeZone,
                        refreshGeneration: refreshGeneration,
                        accountStart: seatStarts[credential.seatID],
                        allTimeBudget: allTimeBudget
                    )
                }
            }
            var collected: [(SeatID, SeatOutcome)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }
    }

    func fetchOne(
        credential: SeatCredential,
        range: UsageRange,
        timeZone: TimeZone,
        refreshGeneration: UInt64? = nil,
        accountStart: UsageDayKey? = nil,
        allTimeBudget: HistoryWarmBudget = .interactiveAllTime
    ) async -> (SeatID, SeatOutcome) {
        if case .allTime(let start, let end) = range {
            let fetchStart = accountStart.map { max($0, start) } ?? start
            guard fetchStart <= end else {
                return (
                    credential.seatID,
                    .refreshed(
                        ActivityAnalyzer.SeatEvents(
                            seatID: credential.seatID,
                            requests: [],
                            truncated: false,
                            reportedTotal: 0
                        )
                    )
                )
            }
            return await fetchAllTimeFromMonths(
                credential: credential,
                start: fetchStart,
                end: end,
                timeZone: timeZone,
                refreshGeneration: refreshGeneration,
                budget: allTimeBudget
            )
        }

        let key = cacheKey(seatID: credential.seatID, range: range)
        if let cached = cache[key], cached.immutable {
            return (credential.seatID, .refreshed(cached.events))
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<(SeatID, SeatOutcome), Never> {
            await self.performFetch(
                credential: credential,
                range: range,
                timeZone: timeZone,
                key: key,
                refreshGeneration: refreshGeneration
            )
        }
        inFlight[key] = task
        let result = await task.value
        if inFlight[key] != nil {
            inFlight[key] = nil
        }
        return result
    }

    func performFetch(
        credential: SeatCredential,
        range: UsageRange,
        timeZone: TimeZone,
        key: CacheKey,
        refreshGeneration: UInt64?
    ) async -> (SeatID, SeatOutcome) {
        if Task.isCancelled {
            return (credential.seatID, .failed)
        }

        let seatID = credential.seatID
        let epoch = bindingEpochBySeat[seatID] ?? 0
        let bounds = range.utcRequestIntervalMs(timeZone: timeZone)
        do {
            let pageResult = try await eventGate.withPermit(seatID: seatID) {
                try await self.pager.fetchAll { page, pageSize in
                    try await self.client.getFilteredUsageEventsPage(
                        access: credential.access,
                        startDateMs: bounds.startMs,
                        endDateMs: bounds.endExclusiveMs,
                        page: page,
                        pageSize: pageSize
                    )
                }
            }
            let events = ActivityAnalyzer.SeatEvents(
                seatID: seatID,
                requests: pageResult.requests,
                truncated: pageResult.truncated,
                reportedTotal: pageResult.reportedTotal
            )
            let immutable: Bool
            if case .month(let month) = range {
                immutable = month < YearMonth.current(timeZone: timeZone) && !pageResult.truncated
            } else {
                immutable = false
            }
            let staged = StagedCacheWrite(
                key: key,
                seatID: seatID,
                epoch: epoch,
                refreshGeneration: refreshGeneration,
                value: CachedSeat(events: events, immutable: immutable)
            )
            guard commitStagedCache(staged) else {
                return (seatID, .failed)
            }
            return (seatID, .refreshed(events))
        } catch {
            guard epoch == (bindingEpochBySeat[seatID] ?? 0) else {
                return (seatID, .failed)
            }
            return (seatID, .failed)
        }
    }

    @discardableResult
    func commitStagedCache(_ staged: StagedCacheWrite) -> Bool {
        if let refreshGeneration = staged.refreshGeneration {
            guard refreshGeneration == generation else { return false }
        }
        guard staged.epoch == (bindingEpochBySeat[staged.seatID] ?? 0) else {
            return false
        }
        cache[staged.key] = staged.value
        return true
    }

    func cacheKey(seatID: SeatID, range: UsageRange) -> CacheKey {
        switch range {
        case .month(let month):
            return .month(seatID, year: month.year, month: month.month)
        case .allTime(let start, let end):
            return .allTime(seatID, start: start, end: end)
        }
    }

    func fetchAllTimeFromMonths(
        credential: SeatCredential,
        start: UsageDayKey,
        end: UsageDayKey,
        timeZone: TimeZone,
        refreshGeneration: UInt64?,
        budget: HistoryWarmBudget
    ) async -> (SeatID, SeatOutcome) {
        let seatID = credential.seatID
        let fullMonths = UsageRangeChunks.months(from: start, through: end, timeZone: timeZone)
        let months = UsageRangeChunks.recentMonths(
            from: start,
            through: end,
            timeZone: timeZone,
            limit: budget.maxMonths
        )
        var merged: [ActivityRequest] = []
        var truncated = months.count < fullMonths.count
        var reportedSum = 0
        var hasReported = false
        var succeededMonths = 0
        var eventsUsed = 0

        for month in months.reversed() {
            if eventsUsed >= budget.maxEvents {
                truncated = true
                break
            }
            let (_, outcome) = await fetchOne(
                credential: credential,
                range: .month(month),
                timeZone: timeZone,
                refreshGeneration: refreshGeneration
            )
            guard case .refreshed(let events) = outcome else {
                truncated = true
                continue
            }
            succeededMonths += 1
            merged.append(contentsOf: events.requests)
            eventsUsed += events.requests.count
            truncated = truncated || events.truncated
            if let reported = events.reportedTotal {
                reportedSum += reported
                hasReported = true
            }
            if reportProgress != nil {
                let partial = ActivityAnalyzer.SeatEvents(
                    seatID: seatID,
                    requests: merged.sorted { $0.timestampMs < $1.timestampMs },
                    truncated: truncated || eventsUsed < budget.maxEvents,
                    reportedTotal: hasReported ? reportedSum : nil
                )
                publishInsightsProgress(
                    outcome: (seatID, .refreshed(partial)),
                    token: refreshGeneration ?? generation
                )
            }
        }

        guard succeededMonths > 0 else {
            return (seatID, .failed)
        }

        let events = ActivityAnalyzer.SeatEvents(
            seatID: seatID,
            requests: merged.sorted { $0.timestampMs < $1.timestampMs },
            truncated: truncated,
            reportedTotal: hasReported ? reportedSum : nil
        )
        return (seatID, .refreshed(events))
    }

    func publishInsightsProgress(
        outcome: (SeatID, SeatOutcome),
        token: UInt64
    ) {
        guard token == generation, reportProgress != nil else { return }
        progressOutcomes[outcome.0] = outcome.1
        var seatEvents: [ActivityAnalyzer.SeatEvents] = []
        for (_, item) in progressOutcomes {
            if case .refreshed(let events) = item {
                seatEvents.append(events)
            }
        }
        guard !seatEvents.isEmpty else { return }
        let insights = ActivityAnalyzer.analyze(
            seats: seatEvents,
            scope: progressScope,
            range: progressRange,
            timeZone: progressTimeZone,
            now: progressNow,
            requestedSeatCount: progressOutcomes.count
        )
        lastInsights = insights
        reportProgress?(Report(insights: insights, outcomes: progressOutcomes))
    }
}
