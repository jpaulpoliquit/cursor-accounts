import CursorBarAdapters
import CursorBarDomain
import Foundation

extension UsageSeriesCoordinator {
    func refresh() {
        task?.cancel()
        generation &+= 1
        let token = generation
        let selectedScope = scope
        phase = .refreshing
        onChange()
        task = Task { [weak self] in
            guard let self else { return }
            if case .allTime = self.range {
                await self.ensureAllTimeBoundsCurrent()
                guard token == self.generation else { return }
            }

            var selectedRange = self.range
            if case .allTime = selectedRange,
               let window = self.allTimeBounds?.chartWindow(for: selectedScope)
            {
                selectedRange = self.interactiveAllTimeRange(window: window)
                self.range = selectedRange
            } else if case .allTime = selectedRange {
                selectedRange = selectedRange.clippedToRecentMonths(
                    HistoryWarmBudget.default.maxMonths,
                    timeZone: self.timeZone
                )
                self.range = selectedRange
            }

            let credentials = self.loadCredentials()
            let seatStarts = self.allTimeBounds?.resolvedStarts ?? [:]
            let fetchRange = selectedRange
            self.insightsPhase = .refreshing
            // Last-known stays on screen until the commit. Per-month progress
            // remounted Swift Charts and retained CollectedChartContent.
            async let seriesCommit = self.refresher.refresh(
                credentials: credentials,
                scope: selectedScope,
                range: fetchRange,
                seatStarts: seatStarts,
                timeZone: self.timeZone
            )
            async let summaryCommit = self.tokenSummaryRefresher.refresh(
                credentials: credentials,
                scope: selectedScope,
                range: fetchRange,
                seatStarts: seatStarts,
                timeZone: self.timeZone
            )
            async let insightsCommit = self.insightsRefresher.refresh(
                credentials: credentials,
                scope: selectedScope,
                range: fetchRange,
                timeZone: self.timeZone,
                seatStarts: seatStarts
            )

            let commit = await seriesCommit
            if token == self.generation, self.range == selectedRange, self.scope == selectedScope {
                self.applySeriesCommit(
                    commit,
                    token: token,
                    selectedRange: selectedRange,
                    selectedScope: selectedScope
                )
            }

            let tokenCommit = await summaryCommit
            if token == self.generation, self.range == selectedRange, self.scope == selectedScope {
                self.applyTokenCommit(
                    tokenCommit,
                    token: token,
                    selectedRange: selectedRange,
                    selectedScope: selectedScope
                )
            }

            if token == self.generation,
               self.range == selectedRange,
               self.scope == selectedScope,
               self.series != nil || self.tokenSummary != nil
            {
                self.phase = .settled
                self.lastSettledAt = Date()
                self.lastSettledScope = selectedScope
                self.lastSettledRange = selectedRange
                self.persistChartSnapshot()
                self.onChange()
            }

            let activityCommit = await insightsCommit
            guard token == self.generation else { return }
            guard self.range == selectedRange, self.scope == selectedScope else { return }
            self.applyInsightsCommit(activityCommit)
            self.persistChartSnapshot()
            self.onChange()
        }
    }

    func applySeriesCommit(
        _ commit: UsageSeriesRefresher.Commit,
        token: UInt64,
        selectedRange: UsageRange,
        selectedScope: UsageScope
    ) {
        guard case .applied(let report) = commit else { return }
        applySeriesReport(
            report,
            token: token,
            selectedRange: selectedRange,
            selectedScope: selectedScope,
            persist: true,
            force: true
        )
    }

    func applySeriesReport(
        _ report: UsageSeriesRefresher.Report,
        token: UInt64,
        selectedRange: UsageRange,
        selectedScope: UsageScope,
        persist: Bool,
        force: Bool = false
    ) {
        guard token == generation else { return }
        guard range == selectedRange, scope == selectedScope else { return }
        let anySuccess = report.outcomes.values.contains {
            if case .refreshed = $0 { return true }
            return false
        }
        guard anySuccess || series == nil else { return }
        let next = report.series.forDisplay(in: selectedRange)
        if !force, !allowsAllTimeGrowth(from: seriesTokenSum(series), to: seriesTokenSum(next), next: selectedRange) {
            return
        }
        if !force, series?.hasPlottablePoints == true, !next.hasPlottablePoints {
            return
        }
        series = next
        lastChunkCount = report.chunkCount
        lastMaxInFlight = report.maxInFlight
        if metric == .costCents, !report.series.costAvailable {
            metric = .tokens
        }
        if persist {
            persistChartSnapshot()
        }
        onChange()
    }

    func applyTokenCommit(
        _ commit: UsageTokenSummaryRefresher.Commit,
        token: UInt64,
        selectedRange: UsageRange,
        selectedScope: UsageScope
    ) {
        guard case .applied(let report) = commit else { return }
        applyTokenReport(
            report,
            token: token,
            selectedRange: selectedRange,
            selectedScope: selectedScope,
            persist: true,
            force: true
        )
    }

    func applyTokenReport(
        _ report: UsageTokenSummaryRefresher.Report,
        token: UInt64,
        selectedRange: UsageRange,
        selectedScope: UsageScope,
        persist: Bool,
        force: Bool = false
    ) {
        guard token == generation else { return }
        guard range == selectedRange, scope == selectedScope else { return }
        let anySuccess = report.outcomes.values.contains {
            if case .refreshed = $0 { return true }
            return false
        }
        guard anySuccess || tokenSummary == nil else { return }
        if !force,
           !allowsAllTimeGrowth(
               from: tokenSummary?.totals.total ?? 0,
               to: report.summary.totals.total,
               next: selectedRange
           )
        {
            return
        }
        tokenSummary = report.summary
        if persist {
            persistChartSnapshot()
        }
        onChange()
    }

    func applyInsightsCommit(_ commit: UsageInsightsRefresher.Commit) {
        switch commit {
        case .applied(let report):
            let anySuccess = report.outcomes.values.contains {
                if case .refreshed = $0 { return true }
                return false
            }
            if anySuccess || insights == nil {
                insights = report.insights
                insightsPhase = .settled
            } else if insights != nil {
                insightsPhase = .settled
            } else {
                insightsPhase = .failed(message: "Work insights unavailable")
            }
        case .discarded:
            if insights == nil {
                insightsPhase = .failed(message: "Work insights unavailable")
            } else {
                insightsPhase = .settled
            }
        }
    }

    func applyInsightsReport(
        _ report: UsageInsightsRefresher.Report,
        token: UInt64,
        selectedRange: UsageRange,
        selectedScope: UsageScope,
        persist: Bool
    ) {
        guard token == generation else { return }
        guard range == selectedRange, scope == selectedScope else { return }
        let nextCount = report.insights.totalRequests
        if let current = insights?.totalRequests,
           case .allTime = selectedRange,
           nextCount < current
        {
            return
        }
        insights = report.insights
        if persist {
            persistChartSnapshot()
        }
        onChange()
    }

    func allowsAllTimeGrowth(from previousTotal: Int64, to nextTotal: Int64, next: UsageRange) -> Bool {
        guard case .allTime = next else { return true }
        guard previousTotal > 0 else { return true }
        return nextTotal >= previousTotal
    }

    func seriesTokenSum(_ series: UsageSeries?) -> Int64 {
        series?.points.reduce(0) { $0 + $1.tokens } ?? 0
    }

    func persistChartSnapshot() {
        guard series != nil || tokenSummary != nil || insights != nil else {
            chartSnapshotStore?.write(nil)
            return
        }
        chartSnapshotStore?.write(
            UsageChartSnapshot(
                series: series,
                tokenSummary: tokenSummary,
                insights: insights,
                scope: scope,
                range: range,
                metric: metric,
                settledAt: lastSettledAt
            )
        )
    }

    func applyHydratedChart(_ snapshot: UsageChartSnapshot) {
        series = snapshot.series
        tokenSummary = snapshot.tokenSummary
        insights = snapshot.insights
        scope = snapshot.scope
        range = snapshot.range
        metric = snapshot.metric
        lastSettledAt = snapshot.settledAt
        if snapshot.series != nil {
            lastSettledScope = snapshot.scope
            lastSettledRange = snapshot.range
            phase = .settled
        }
        if snapshot.insights != nil {
            insightsPhase = .settled
        }
    }

    func interactiveAllTimeRange(window: (start: UsageDayKey, end: UsageDayKey)) -> UsageRange {
        UsageRange.allTime(start: window.start, end: window.end)
            .clippedToRecentMonths(HistoryWarmBudget.default.maxMonths, timeZone: timeZone)
    }

    func ensureAllTimeBoundsCurrent() async {
        let today = UsageDayKey.utcDay(containing: Date())
        let credentials = loadCredentials()
        guard !credentials.isEmpty else { return }

        let seatIDs = Set(credentials.map(\.seatID))
        let existingSeats = Set(allTimeBounds?.perSeat.keys.map { $0 } ?? [])
        let needsResolve = allTimeBounds == nil
            || !seatIDs.isSubset(of: existingSeats)
            || (allTimeBounds?.isPartial == true)

        if needsResolve {
            if let resolved = await resolveAllTimeBounds() {
                allTimeBounds = resolved.refreshingEnd(to: today)
                onChange()
            } else if let existing = allTimeBounds {
                allTimeBounds = existing.refreshingEnd(to: today)
            }
        } else if let existing = allTimeBounds {
            allTimeBounds = existing.refreshingEnd(to: today)
        }
    }
}
