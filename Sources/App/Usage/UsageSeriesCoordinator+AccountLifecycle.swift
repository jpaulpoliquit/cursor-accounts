import CursorBarAdapters
import CursorBarDomain
import Foundation

extension UsageSeriesCoordinator {
    /// Fire-and-forget recent-first history warm for a seat that just signed in.
    /// Restarting the same seat cancels only that seat; other seats keep warming.
    func warmHistory(for seatID: SeatID) {
        warmTasks[seatID]?.cancel()
        let token = (warmGenerations[seatID] ?? 0) &+ 1
        warmGenerations[seatID] = token
        let task = Task { [weak self] in
            guard let self else { return }
            let credentials = self.loadCredentials()
            guard let credential = credentials.first(where: { $0.seatID == seatID }) else {
                guard self.warmGenerations[seatID] == token else { return }
                self.historyWarmPhasesBySeat[seatID] = .idle
                self.publishHistoryWarmPhase()
                return
            }
            guard self.warmGenerations[seatID] == token else { return }
            self.historyWarmPhasesBySeat[seatID] = .warming(
                completedMonths: 0,
                targetMonths: HistoryWarmBudget.default.maxMonths
            )
            self.publishHistoryWarmPhase()
            await self.refresher.armWarm(seatID: seatID, token: token)
            await self.tokenSummaryRefresher.armWarm(seatID: seatID, token: token)
            await self.insightsRefresher.armWarm(seatID: seatID, token: token)
            let phase = await self.warmAllCaches(
                credential: credential,
                seatID: seatID,
                warmToken: token
            ) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.warmGenerations[seatID] == token else { return }
                    self.historyWarmPhasesBySeat[seatID] = progress
                    self.publishHistoryWarmPhase()
                }
            }
            guard self.warmGenerations[seatID] == token else { return }
            self.historyWarmPhasesBySeat[seatID] = phase
            self.warmTasks[seatID] = nil
            self.publishHistoryWarmPhase()
        }
        warmTasks[seatID] = task
    }

    /// Warm every connected signed-in seat. Does not block UI.
    func warmAllConnectedSeats() {
        for credential in loadCredentials() {
            warmHistory(for: credential.seatID)
        }
    }

    /// Resume warm only for seats that are not already warming or settled.
    func warmConnectedSeatsIfNeeded() {
        for credential in loadCredentials() {
            switch historyWarmPhase(for: credential.seatID) {
            case .warming, .settled:
                continue
            case .idle, .cancelled:
                warmHistory(for: credential.seatID)
            }
        }
    }

    /// Cancel history warm and drop raw fetch caches. Compact last-known stays.
    func pauseBackgroundWork() {
        for seatID in Array(warmTasks.keys) {
            cancelWarm(for: seatID)
        }
        Task { [weak self] in
            await self?.releaseIdleCaches()
        }
    }

    /// Hidden surface does not keep raw event months or historical chunk caches.
    func releaseIdleCaches() async {
        let keepCurrentMonth = UsageWorkPolicy.retainsRawEventMonths(.hidden)
        await insightsRefresher.releaseRawEvents(keepingCurrentMonth: keepCurrentMonth)
        await refresher.releaseHistoricalChunks(keepingCurrentMonth: keepCurrentMonth)
        await tokenSummaryRefresher.releaseHistoricalMonths(keepingCurrentMonth: keepCurrentMonth)
    }

    private func warmAllCaches(
        credential: UsageSeriesRefresher.SeatCredential,
        seatID: SeatID,
        warmToken: UInt64,
        onProgress: (@Sendable (HistoryWarmPhase) -> Void)?
    ) async -> HistoryWarmPhase {
        let budget = HistoryWarmBudget.default
        let target = max(1, budget.maxMonths)
        var warmed = 0
        var eventsUsed = 0
        var month = YearMonth.current(timeZone: timeZone)
        onProgress?(.warming(completedMonths: 0, targetMonths: target))

        while warmed < target, eventsUsed < budget.maxEvents {
            guard warmGenerations[seatID] == warmToken else {
                onProgress?(.cancelled)
                return .cancelled
            }

            let fetchMonth = month
            async let insightTask = insightsRefresher.warmMonth(
                credential: credential,
                month: fetchMonth,
                timeZone: timeZone,
                warmToken: warmToken
            )
            async let seriesTask = refresher.warmMonth(
                credential: credential,
                month: fetchMonth,
                timeZone: timeZone,
                warmToken: warmToken
            )
            async let tokensTask = tokenSummaryRefresher.warmMonth(
                credential: credential,
                month: fetchMonth,
                timeZone: timeZone,
                warmToken: warmToken
            )
            let insightResult = await insightTask
            _ = await seriesTask
            _ = await tokensTask

            guard warmGenerations[seatID] == warmToken else {
                onProgress?(.cancelled)
                return .cancelled
            }

            if let eventsUsedCount = insightResult {
                eventsUsed += eventsUsedCount
                warmed += 1
                onProgress?(.warming(completedMonths: warmed, targetMonths: target))
            } else {
                break
            }

            month = month.previous
        }

        guard warmGenerations[seatID] == warmToken else {
            onProgress?(.cancelled)
            return .cancelled
        }
        let settled = HistoryWarmPhase.settled(warmedMonths: warmed)
        onProgress?(settled)
        return settled
    }

    /// Account-removal lifecycle at the usage boundary.
    /// Synchronously clears visible state, then awaits actor purge before callers may refresh/warm.
    func purgeAccount(for seatID: SeatID, bindingEpoch: UInt64) async {
        cancelWarm(for: seatID)
        let scopeIncludesSeat: Bool
        switch scope {
        case .allAccounts:
            scopeIncludesSeat = true
        case .account(let id):
            scopeIncludesSeat = id == seatID
        }
        if scopeIncludesSeat {
            task?.cancel()
            generation &+= 1
            clearVisibleState(including: seatID)
        }
        if let bounds = allTimeBounds {
            var perSeat = bounds.perSeat
            perSeat.removeValue(forKey: seatID)
            allTimeBounds = perSeat.isEmpty
                ? nil
                : AllTimeHistoryBounds(endDay: bounds.endDay, perSeat: perSeat)
        }
        onChange()

        await refresher.invalidateBinding(seatID: seatID, epoch: bindingEpoch)
        await tokenSummaryRefresher.invalidateBinding(seatID: seatID, epoch: bindingEpoch)
        await insightsRefresher.invalidateBinding(seatID: seatID, epoch: bindingEpoch)
    }

    /// After purge completes, refresh if credentials remain.
    func refreshAfterAccountPurgeIfNeeded() {
        guard !loadCredentials().isEmpty else {
            phase = .idle
            insightsPhase = .idle
            onChange()
            return
        }
        refresh()
    }

    func historyWarmPhase(for seatID: SeatID) -> HistoryWarmPhase {
        historyWarmPhasesBySeat[seatID] ?? .idle
    }

    private func cancelWarm(for seatID: SeatID) {
        warmTasks[seatID]?.cancel()
        warmTasks[seatID] = nil
        warmGenerations[seatID] = (warmGenerations[seatID] ?? 0) &+ 1
        historyWarmPhasesBySeat[seatID] = .idle
        publishHistoryWarmPhase()
    }

    private func clearVisibleState(including seatID: SeatID) {
        let includes: Bool
        switch scope {
        case .allAccounts:
            includes = true
        case .account(let id):
            includes = id == seatID
        }
        guard includes else { return }
        if case .account(let id) = scope, id == seatID {
            scope = .allAccounts
        }
        series = nil
        tokenSummary = nil
        insights = nil
        phase = .idle
        insightsPhase = .idle
        lastSettledAt = nil
        lastSettledScope = nil
        lastSettledRange = nil
        persistChartSnapshot()
    }

    private func publishHistoryWarmPhase() {
        if let warming = historyWarmPhasesBySeat.values.first(where: {
            if case .warming = $0 { return true }
            return false
        }) {
            historyWarmPhase = warming
        } else {
            historyWarmPhase = .idle
        }
        onChange()
    }
}
