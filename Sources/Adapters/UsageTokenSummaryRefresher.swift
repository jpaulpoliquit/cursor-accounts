import CursorBarDomain
import Foundation

/// Parallel per-account Aggregate fetch with historical-month cache, All Time chunking, and generation cancel.
public actor UsageTokenSummaryRefresher {
    public typealias SeatCredential = SeatUsageRefresher.SeatCredential

    public enum SeatSummaryOutcome: Sendable, Equatable {
        case refreshed(SeatUsageTokenSummary, TemporalCoverage?)
        case failed
        case skippedSignedOut
    }

    public struct Report: Sendable, Equatable {
        public let summary: UsageTokenSummary
        public let outcomes: [SeatID: SeatSummaryOutcome]

        public init(summary: UsageTokenSummary, outcomes: [SeatID: SeatSummaryOutcome]) {
            self.summary = summary
            self.outcomes = outcomes
        }
    }

    public enum Commit: Sendable, Equatable {
        case applied(Report)
        case discarded
    }

    enum CacheKey: Hashable, Sendable {
        case month(SeatID, year: Int, month: Int)
    }

    public static let maxConcurrentChunks = FetchConcurrencyGate.defaultLimit

    let client: DashboardClient
    let chunkGate: FetchConcurrencyGate
    var lastSummary: UsageTokenSummary?
    var cache: [CacheKey: SeatUsageTokenSummary] = [:]
    var generation: UInt64 = 0
    var warmGenerationBySeat: [SeatID: UInt64] = [:]
    /// Per-seat binding identity from App lifecycle. Set via invalidateBinding before rebind.
    var bindingEpochBySeat: [SeatID: UInt64] = [:]
    var reportProgress: (@Sendable (Report) -> Void)?
    var progressOutcomes: [SeatID: SeatSummaryOutcome] = [:]
    var progressRequested = 0
    var progressScope: UsageScope = .allAccounts
    var progressRange: UsageRange = .defaultMonth()
    var progressNow = Date()

    public init(
        client: DashboardClient = DashboardClient(),
        maxConcurrentChunks: Int = UsageTokenSummaryRefresher.maxConcurrentChunks,
        gate: FetchConcurrencyGate? = nil
    ) {
        self.client = client
        self.chunkGate = gate ?? FetchConcurrencyGate(limit: maxConcurrentChunks)
    }

    public func lastKnownSummary() -> UsageTokenSummary? { lastSummary }

    public func monthCacheEntryCount() -> Int { cache.count }

    /// Drop historical Aggregate month rows. Last-known summary stays.
    public func releaseHistoricalMonths(
        keepingCurrentMonth: Bool,
        timeZone: TimeZone = .current,
        now: Date = Date()
    ) {
        if keepingCurrentMonth {
            let current = YearMonth.current(now: now, timeZone: timeZone)
            cache = cache.filter { key, _ in
                switch key {
                case .month(_, let year, let month):
                    return year == current.year && month == current.month
                }
            }
        } else {
            cache.removeAll()
        }
    }

    /// Invalidate reusable SeatID caches before the seat can be rebound. Does not touch other seats.
    public func invalidateBinding(seatID: SeatID, epoch: UInt64) {
        generation &+= 1
        warmGenerationBySeat[seatID] = (warmGenerationBySeat[seatID] ?? 0) &+ 1
        bindingEpochBySeat[seatID] = epoch
        cache = cache.filter { key, _ in
            switch key {
            case .month(let id, _, _):
                return id != seatID
            }
        }
        if let last = lastSummary {
            switch last.scope {
            case .account(let id) where id == seatID:
                lastSummary = nil
            case .allAccounts:
                lastSummary = nil
            case .account:
                break
            }
        }
    }

    public func dropSeatCaches(seatID: SeatID) {
        invalidateBinding(seatID: seatID, epoch: (bindingEpochBySeat[seatID] ?? 0) &+ 1)
    }

    public func refresh(
        credentials: [SeatCredential],
        scope: UsageScope,
        range: UsageRange,
        seatStarts: [SeatID: UsageDayKey] = [:],
        timeZone: TimeZone = .current,
        now: Date = Date(),
        onProgress: (@Sendable (Report) -> Void)? = nil
    ) async -> Commit {
        generation &+= 1
        let token = generation
        reportProgress = onProgress
        progressOutcomes = [:]
        progressRequested = credentials.count
        progressScope = scope
        progressRange = range
        progressNow = now
        defer {
            if token == generation {
                reportProgress = nil
            }
        }

        switch scope {
        case .allAccounts:
            let fetched = await fetchAll(
                credentials: credentials,
                range: range,
                seatStarts: seatStarts,
                timeZone: timeZone,
                token: token
            )
            guard token == generation else { return .discarded }
            return commit(
                fetched: fetched,
                requested: credentials.count,
                scope: .allAccounts,
                range: range,
                now: now
            )

        case .account(let seatID):
            guard let credential = credentials.first(where: { $0.seatID == seatID }) else {
                guard token == generation else { return .discarded }
                let empty = UsageTokenSummaryAggregator.aggregate(
                    successful: [],
                    requestedAccountCount: 1,
                    scope: .account(seatID),
                    range: range,
                    fetchedAt: now
                )
                return .applied(Report(summary: empty, outcomes: [seatID: .skippedSignedOut]))
            }
            let outcome = await fetchOne(
                credential: credential,
                range: range,
                accountStart: seatStarts[seatID],
                timeZone: timeZone,
                token: token
            )
            guard token == generation else { return .discarded }
            return commit(
                fetched: [outcome],
                requested: 1,
                scope: .account(seatID),
                range: range,
                now: now
            )
        }
    }

    private func fetchAll(
        credentials: [SeatCredential],
        range: UsageRange,
        seatStarts: [SeatID: UsageDayKey],
        timeZone: TimeZone,
        token: UInt64
    ) async -> [(SeatID, SeatSummaryOutcome)] {
        await withTaskGroup(of: (SeatID, SeatSummaryOutcome).self) { group in
            for credential in credentials {
                group.addTask {
                    await self.fetchOne(
                        credential: credential,
                        range: range,
                        accountStart: seatStarts[credential.seatID],
                        timeZone: timeZone,
                        token: token
                    )
                }
            }
            var collected: [(SeatID, SeatSummaryOutcome)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }
    }

    private func fetchOne(
        credential: SeatCredential,
        range: UsageRange,
        accountStart: UsageDayKey?,
        timeZone: TimeZone,
        token: UInt64
    ) async -> (SeatID, SeatSummaryOutcome) {
        switch range {
        case .month(let month):
            return await fetchMonth(
                credential: credential,
                month: month,
                timeZone: timeZone,
                token: token
            )
        case .allTime(let start, let end):
            let fetchStart = accountStart ?? start
            guard fetchStart <= end else {
                return (
                    credential.seatID,
                    .refreshed(
                        SeatUsageTokenSummary(seatID: credential.seatID, totals: .zero, models: []),
                        .complete(from: fetchStart, through: end)
                    )
                )
            }
            return await fetchAllTimeChunked(
                credential: credential,
                start: fetchStart,
                end: end,
                timeZone: timeZone,
                token: token
            )
        }
    }

    private func fetchMonth(
        credential: SeatCredential,
        month: YearMonth,
        timeZone: TimeZone,
        token: UInt64
    ) async -> (SeatID, SeatSummaryOutcome) {
        let key = CacheKey.month(credential.seatID, year: month.year, month: month.month)
        let current = YearMonth.current(timeZone: timeZone)
        if month < current, let cached = cache[key] {
            return (credential.seatID, .refreshed(cached, nil))
        }
        let epoch = bindingEpochBySeat[credential.seatID] ?? 0
        let bounds = month.utcHalfOpenIntervalMs(timeZone: timeZone)
        do {
            let summary = try await client.getAggregatedUsageEvents(
                access: credential.access,
                startDateMs: bounds.startMs,
                endDateMs: bounds.endExclusiveMs,
                seatID: credential.seatID
            )
            let staged: [CacheKey: SeatUsageTokenSummary] = month < current ? [key: summary] : [:]
            guard commitTokenCache(
                seatID: credential.seatID,
                token: token,
                epoch: epoch,
                writes: staged
            ) else {
                return (credential.seatID, .failed)
            }
            return (credential.seatID, .refreshed(summary, nil))
        } catch {
            return (credential.seatID, .failed)
        }
    }

    public func armWarm(seatID: SeatID, token: UInt64) {
        warmGenerationBySeat[seatID] = token
    }

    public func warmMonth(
        credential: SeatCredential,
        month: YearMonth,
        timeZone: TimeZone,
        warmToken: UInt64
    ) async -> Bool {
        let seatID = credential.seatID
        guard warmToken == warmGenerationBySeat[seatID] else { return false }
        let key = CacheKey.month(seatID, year: month.year, month: month.month)
        let current = YearMonth.current(timeZone: timeZone)
        if month < current, cache[key] != nil {
            return true
        }
        let epoch = bindingEpochBySeat[seatID] ?? 0
        let bounds = month.utcHalfOpenIntervalMs(timeZone: timeZone)
        do {
            let summary = try await client.getAggregatedUsageEvents(
                access: credential.access,
                startDateMs: bounds.startMs,
                endDateMs: bounds.endExclusiveMs,
                seatID: seatID
            )
            let staged: [CacheKey: SeatUsageTokenSummary] = month < current ? [key: summary] : [:]
            return commitWarmTokenCache(
                seatID: seatID,
                epoch: epoch,
                warmToken: warmToken,
                writes: staged,
                summary: summary
            )
        } catch {
            return false
        }
    }
}
