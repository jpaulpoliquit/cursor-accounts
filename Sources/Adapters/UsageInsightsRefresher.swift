import CursorBarDomain
import Foundation

/// Fetches and caches activity events for Insights. No menu-bar polling.
public actor UsageInsightsRefresher {
    public typealias SeatCredential = SeatUsageRefresher.SeatCredential

    public enum SeatOutcome: Sendable, Equatable {
        case refreshed(ActivityAnalyzer.SeatEvents)
        case failed
        case skippedSignedOut
    }

    public struct Report: Sendable, Equatable {
        public let insights: ActivityInsights
        public let outcomes: [SeatID: SeatOutcome]

        public init(insights: ActivityInsights, outcomes: [SeatID: SeatOutcome]) {
            self.insights = insights
            self.outcomes = outcomes
        }
    }

    public enum Commit: Sendable, Equatable {
        case applied(Report)
        case discarded
    }

    enum CacheKey: Hashable, Sendable {
        case month(SeatID, year: Int, month: Int)
        case allTime(SeatID, start: UsageDayKey, end: UsageDayKey)
    }

    struct CachedSeat: Sendable, Equatable {
        var events: ActivityAnalyzer.SeatEvents
        var immutable: Bool
    }

    /// Staged cache mutation; committed only while generation + seat epoch stay current.
    struct StagedCacheWrite: Sendable {
        let key: CacheKey
        let seatID: SeatID
        let epoch: UInt64
        let refreshGeneration: UInt64?
        let value: CachedSeat
    }

    let client: DashboardClient
    let pager: UsageEventsPager
    let eventGate: FetchConcurrencyGate
    var cache: [CacheKey: CachedSeat] = [:]
    var inFlight: [CacheKey: Task<(SeatID, SeatOutcome), Never>] = [:]
    var lastInsights: ActivityInsights?
    var generation: UInt64 = 0
    /// Per-seat warm generations so one seat's cancel/restart never aborts another.
    var warmGenerationBySeat: [SeatID: UInt64] = [:]
    /// Per-seat binding identity from App lifecycle. Set via invalidateBinding before rebind.
    var bindingEpochBySeat: [SeatID: UInt64] = [:]
    var reportProgress: (@Sendable (Report) -> Void)?
    var progressOutcomes: [SeatID: SeatOutcome] = [:]
    var progressScope: UsageScope = .allAccounts
    var progressRange: UsageRange = .defaultMonth()
    var progressTimeZone: TimeZone = .current
    var progressNow = Date()

    public init(
        client: DashboardClient = DashboardClient(),
        pager: UsageEventsPager = UsageEventsPager(),
        maxConcurrentFetches: Int = FetchConcurrencyGate.defaultLimit,
        gate: FetchConcurrencyGate? = nil
    ) {
        self.client = client
        self.pager = pager
        self.eventGate = gate ?? FetchConcurrencyGate(limit: maxConcurrentFetches)
    }

    public func maxObservedInFlight() async -> Int {
        await eventGate.maxObservedInFlight
    }

    public func lastKnownInsights() -> ActivityInsights? { lastInsights }

    public func eventCacheEntryCount() -> Int { cache.count }

    /// Drop past-month and all-time event arrays. Current month can stay for the next open.
    public func releaseRawEvents(
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
                case .allTime:
                    return false
                }
            }
        } else {
            cache.removeAll()
        }
    }

    public func refresh(
        credentials: [SeatCredential],
        scope: UsageScope,
        range: UsageRange,
        timeZone: TimeZone = .current,
        now: Date = Date(),
        includeMonthOverMonth: Bool = true,
        seatStarts: [SeatID: UsageDayKey] = [:],
        allTimeBudget: HistoryWarmBudget = .interactiveAllTime,
        onProgress: (@Sendable (Report) -> Void)? = nil
    ) async -> Commit {
        generation &+= 1
        let token = generation
        reportProgress = onProgress
        progressOutcomes = [:]
        progressScope = scope
        progressRange = range
        progressTimeZone = timeZone
        progressNow = now
        defer {
            if token == generation {
                reportProgress = nil
            }
        }
        let deduped = Self.dedupeSameSubject(credentials)

        let selected: [SeatCredential]
        switch scope {
        case .allAccounts:
            selected = deduped
        case .account(let seatID):
            guard let credential = deduped.first(where: { $0.seatID == seatID })
                    ?? credentials.first(where: { $0.seatID == seatID })
            else {
                guard token == generation else { return .discarded }
                let empty = ActivityAnalyzer.analyze(
                    seats: [],
                    scope: scope,
                    range: range,
                    timeZone: timeZone,
                    now: now,
                    requestedSeatCount: 1
                )
                return .applied(Report(insights: empty, outcomes: [seatID: .skippedSignedOut]))
            }
            selected = [credential]
        }

        let fetched = await fetchSeats(
            selected,
            range: range,
            timeZone: timeZone,
            refreshGeneration: token,
            seatStarts: seatStarts,
            allTimeBudget: allTimeBudget
        )
        guard token == generation else { return .discarded }

        var previous: [ActivityAnalyzer.SeatEvents]?
        var previousRequested: Int?
        if includeMonthOverMonth, case .month(let month) = range {
            let previousRange = UsageRange.month(month.previous)
            let prevFetched = await fetchSeats(selected, range: previousRange, timeZone: timeZone, refreshGeneration: token)
            guard token == generation else { return .discarded }
            previous = prevFetched.compactMap { _, outcome in
                if case .refreshed(let events) = outcome { return events }
                return nil
            }
            previousRequested = selected.count
        }

        guard token == generation else { return .discarded }

        var outcomes: [SeatID: SeatOutcome] = [:]
        var seatEvents: [ActivityAnalyzer.SeatEvents] = []
        for (seatID, outcome) in fetched {
            outcomes[seatID] = outcome
            if case .refreshed(let events) = outcome {
                seatEvents.append(events)
            }
        }

        let insights = ActivityAnalyzer.analyze(
            seats: seatEvents,
            scope: scope,
            range: range,
            timeZone: timeZone,
            now: now,
            previousMonthSeats: previous,
            requestedSeatCount: selected.count,
            previousRequestedSeatCount: previousRequested
        )

        if seatEvents.isEmpty {
            // Do not let an all-fail overwrite last-known into a falsely complete empty report.
            if let previousKnown = lastInsights,
               previousKnown.scope == scope,
               previousKnown.range == range
            {
                return .applied(Report(insights: previousKnown, outcomes: outcomes))
            }
            if lastInsights == nil {
                lastInsights = insights
            }
            return .applied(Report(insights: insights, outcomes: outcomes))
        }

        lastInsights = insights
        return .applied(Report(insights: insights, outcomes: outcomes))
    }

    /// Warm one month for Insights cache. Joins in-flight month fetch when present.
    public func warmMonth(
        credential: SeatCredential,
        month: YearMonth,
        timeZone: TimeZone = .current,
        warmToken: UInt64? = nil
    ) async -> Int? {
        let seatID = credential.seatID
        if let warmToken {
            guard warmToken == warmGenerationBySeat[seatID] else { return nil }
        }
        let range = UsageRange.month(month)
        let (_, outcome) = await fetchOne(
            credential: credential,
            range: range,
            timeZone: timeZone
        )
        if let warmToken {
            guard warmToken == warmGenerationBySeat[seatID] else { return nil }
        }
        guard case .refreshed(let events) = outcome else { return nil }
        return events.requests.count
    }

    /// Recent-first background warm for one seat. Restarting the same seat cancels only that seat's prior warm.
    public func warmSeatHistory(
        credential: SeatCredential,
        timeZone: TimeZone = .current,
        now: Date = Date(),
        budget: HistoryWarmBudget = .default,
        onProgress: (@Sendable (HistoryWarmPhase) -> Void)? = nil
    ) async -> HistoryWarmPhase {
        let seatID = credential.seatID
        let token = (warmGenerationBySeat[seatID] ?? 0) &+ 1
        warmGenerationBySeat[seatID] = token
        let target = max(1, budget.maxMonths)
        var warmed = 0
        var eventsUsed = 0
        var month = YearMonth.current(timeZone: timeZone)
        onProgress?(.warming(completedMonths: 0, targetMonths: target))

        while warmed < target, eventsUsed < budget.maxEvents {
            guard token == warmGenerationBySeat[seatID] else {
                onProgress?(.cancelled)
                return .cancelled
            }
            guard let result = await warmMonth(
                credential: credential,
                month: month,
                timeZone: timeZone,
                warmToken: token
            ) else {
                break
            }
            eventsUsed += result
            warmed += 1
            onProgress?(.warming(completedMonths: warmed, targetMonths: target))
            month = month.previous
            _ = now
        }

        guard token == warmGenerationBySeat[seatID] else {
            onProgress?(.cancelled)
            return .cancelled
        }
        let settled = HistoryWarmPhase.settled(warmedMonths: warmed)
        onProgress?(settled)
        return settled
    }

    public func armWarm(seatID: SeatID, token: UInt64) {
        warmGenerationBySeat[seatID] = token
    }

    /// Drop memory caches and cancel warm for a signed-out seat. Other seats keep warming.
    public func invalidateBinding(seatID: SeatID, epoch: UInt64) {
        generation &+= 1
        warmGenerationBySeat[seatID] = (warmGenerationBySeat[seatID] ?? 0) &+ 1
        bindingEpochBySeat[seatID] = epoch
        cache = cache.filter { key, _ in
            switch key {
            case .month(let id, _, _):
                return id != seatID
            case .allTime(let id, _, _):
                return id != seatID
            }
        }
        for (key, task) in inFlight {
            let matches: Bool
            switch key {
            case .month(let id, _, _):
                matches = id == seatID
            case .allTime(let id, _, _):
                matches = id == seatID
            }
            if matches {
                task.cancel()
                inFlight[key] = nil
            }
        }
        if let last = lastInsights {
            switch last.scope {
            case .account(let id) where id == seatID:
                lastInsights = nil
            case .allAccounts:
                lastInsights = nil
            case .account:
                break
            }
        }
    }

    public func dropSeatCaches(seatID: SeatID) {
        invalidateBinding(seatID: seatID, epoch: (bindingEpochBySeat[seatID] ?? 0) &+ 1)
    }

    /// Test helper: advance generation so in-flight work discards.
    public func bumpGenerationForTests() {
        generation &+= 1
    }

    /// Drops later seats that share a JWT subject with an earlier seat.
    static func dedupeSameSubject(_ credentials: [SeatCredential]) -> [SeatCredential] {
        var seen = Set<String>()
        var result: [SeatCredential] = []
        for credential in credentials {
            guard let subject = JWTClaims.decode(jwt: credential.access.rawValue)?.subject else {
                result.append(credential)
                continue
            }
            let normalized = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                result.append(credential)
                continue
            }
            if seen.contains(normalized) {
                continue
            }
            seen.insert(normalized)
            result.append(credential)
        }
        return result
    }
}
