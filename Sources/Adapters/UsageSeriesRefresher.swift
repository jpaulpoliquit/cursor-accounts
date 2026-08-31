import CursorBarDomain
import Foundation

/// Parallel per-account daily series fetch with last-known retention, chunk cache, and generation cancel.
public actor UsageSeriesRefresher {
    public typealias SeatCredential = SeatUsageRefresher.SeatCredential

    public enum SeatSeriesOutcome: Sendable, Equatable {
        case refreshed(SeatUsageSeries)
        case failed
        case skippedSignedOut
    }

    public struct Report: Sendable, Equatable {
        public let series: UsageSeries
        public let outcomes: [SeatID: SeatSeriesOutcome]
        public let chunkCount: Int
        public let maxInFlight: Int

        public init(
            series: UsageSeries,
            outcomes: [SeatID: SeatSeriesOutcome],
            chunkCount: Int = 1,
            maxInFlight: Int = 0
        ) {
            self.series = series
            self.outcomes = outcomes
            self.chunkCount = chunkCount
            self.maxInFlight = maxInFlight
        }
    }

    public enum Commit: Sendable, Equatable {
        case applied(Report)
        case discarded
    }

    /// Default shared-lane cap when tests construct a private gate.
    public static let maxConcurrentChunks = FetchConcurrencyGate.defaultLimit

    let client: DashboardClient
    let chunkGate: FetchConcurrencyGate
    var lastKnownBySeat: [SeatID: SeatUsageSeries] = [:]
    var lastSeries: UsageSeries?
    var chunkCache: [UsageSeriesChunkKey: SeatUsageSeries] = [:]
    var networkFetchCounts: [UsageSeriesChunkKey: Int] = [:]
    var generation: UInt64 = 0
    /// Per-seat warm generations; bumped with invalidateBinding and armWarm.
    var warmGenerationBySeat: [SeatID: UInt64] = [:]
    /// Per-seat binding identity from App lifecycle. Set via invalidateBinding before rebind.
    var bindingEpochBySeat: [SeatID: UInt64] = [:]
    var reportProgress: (@Sendable (Report) -> Void)?
    var progressOutcomes: [SeatID: SeatSeriesOutcome] = [:]
    var progressRequested = 0
    var progressScope: UsageScope = .allAccounts
    var progressRangeStart = UsageDayKey.utcDay(containing: Date())
    var progressRangeEnd = UsageDayKey.utcDay(containing: Date())

    public init(
        client: DashboardClient = DashboardClient(),
        maxConcurrentChunks: Int = UsageSeriesRefresher.maxConcurrentChunks,
        gate: FetchConcurrencyGate? = nil
    ) {
        self.client = client
        self.chunkGate = gate ?? FetchConcurrencyGate(limit: maxConcurrentChunks)
    }

    public func lastKnownSeries() -> UsageSeries? { lastSeries }

    public func chunkCacheEntryCount() -> Int { chunkCache.count }

    /// Drop month chunk arrays. Last-known aggregated series stays.
    public func releaseHistoricalChunks(keepingCurrentMonth: Bool, timeZone: TimeZone = .current, now: Date = Date()) {
        if keepingCurrentMonth {
            let current = YearMonth.current(now: now, timeZone: timeZone)
            chunkCache = chunkCache.filter { $0.key.year == current.year && $0.key.month == current.month }
        } else {
            chunkCache.removeAll()
        }
    }

    public func networkFetchCount(seatID: SeatID, month: YearMonth) -> Int {
        networkFetchCounts[UsageSeriesChunkKey(seatID: seatID, month: month)] ?? 0
    }

    public func maxObservedInFlight() async -> Int {
        await chunkGate.maxObservedInFlight
    }

    /// Invalidate reusable SeatID caches before the seat can be rebound. Does not touch other seats.
    public func invalidateBinding(seatID: SeatID, epoch: UInt64) {
        generation &+= 1
        warmGenerationBySeat[seatID] = (warmGenerationBySeat[seatID] ?? 0) &+ 1
        bindingEpochBySeat[seatID] = epoch
        lastKnownBySeat[seatID] = nil
        chunkCache = chunkCache.filter { $0.key.seatID != seatID }
        networkFetchCounts = networkFetchCounts.filter { $0.key.seatID != seatID }
        if let last = lastSeries {
            switch last.scope {
            case .account(let id) where id == seatID:
                lastSeries = nil
            case .allAccounts:
                lastSeries = nil
            case .account:
                break
            }
        }
    }

    /// Compatibility alias; prefer invalidateBinding with App-owned epoch.
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
        _ = now
        generation &+= 1
        let token = generation
        let days = range.chartUTCDays(timeZone: timeZone)
        reportProgress = onProgress
        progressOutcomes = [:]
        progressRequested = credentials.count
        progressScope = scope
        progressRangeStart = days.start
        progressRangeEnd = days.end
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
                chartStart: days.start,
                chartEnd: days.end,
                seatStarts: seatStarts,
                timeZone: timeZone,
                token: token
            )
            guard token == generation else { return .discarded }
            let maxInFlight = await chunkGate.maxObservedInFlight
            return commit(
                fetched: fetched.outcomes,
                requested: credentials.count,
                scope: .allAccounts,
                rangeStart: days.start,
                rangeEnd: days.end,
                chunkCount: fetched.chunkCount,
                missingMonthCount: fetched.missingMonthCount,
                maxInFlight: maxInFlight
            )

        case .account(let seatID):
            guard let credential = credentials.first(where: { $0.seatID == seatID }) else {
                guard token == generation else { return .discarded }
                let empty = UsageSeriesAggregator.aggregate(
                    successful: [],
                    requestedAccountCount: 1,
                    scope: .account(seatID),
                    rangeStart: days.start,
                    rangeEnd: days.end
                )
                return .applied(
                    Report(series: empty, outcomes: [seatID: .skippedSignedOut], chunkCount: 0)
                )
            }
            let fetched = await fetchOne(
                credential: credential,
                range: range,
                chartStart: days.start,
                chartEnd: days.end,
                accountStart: seatStarts[seatID],
                timeZone: timeZone,
                token: token
            )
            guard token == generation else { return .discarded }
            let maxInFlight = await chunkGate.maxObservedInFlight
            return commit(
                fetched: [fetched.outcome],
                requested: 1,
                scope: .account(seatID),
                rangeStart: days.start,
                rangeEnd: days.end,
                chunkCount: fetched.chunkCount,
                missingMonthCount: fetched.missingMonthCount,
                maxInFlight: maxInFlight
            )
        }
    }

    public func armWarm(seatID: SeatID, token: UInt64) {
        warmGenerationBySeat[seatID] = token
    }

    /// Warm one month into chunk cache without starting a dashboard refresh generation.
    public func warmMonth(
        credential: SeatCredential,
        month: YearMonth,
        timeZone: TimeZone,
        warmToken: UInt64
    ) async -> Bool {
        let seatID = credential.seatID
        guard warmToken == warmGenerationBySeat[seatID] else { return false }
        let key = UsageSeriesChunkKey(seatID: seatID, month: month)
        let currentMonth = YearMonth.current(timeZone: timeZone)
        if month < currentMonth, chunkCache[key] != nil {
            return true
        }
        let epoch = bindingEpochBySeat[seatID] ?? 0
        let monthDays = month.overlappingUTCDays(timeZone: timeZone)
        let bounds = month.utcHalfOpenIntervalMs(timeZone: timeZone)
        do {
            let rows = try await client.getDailySpendByCategory(
                access: credential.access,
                periodStartMs: bounds.startMs,
                periodEndMs: bounds.endExclusiveMs
            )
            let staged = UsageSeriesAggregator.seatSeries(
                seatID: seatID,
                rows: rows,
                rangeStart: monthDays.start,
                rangeEnd: monthDays.end,
                accountStart: nil
            )
            return commitWarmSeriesCache(
                seatID: seatID,
                epoch: epoch,
                warmToken: warmToken,
                writes: [key: staged],
                networkIncrements: [key]
            )
        } catch {
            return false
        }
    }

}
