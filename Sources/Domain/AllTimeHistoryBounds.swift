import Foundation

/// Per-seat account-age start from `GetMe.createdAt` (UTC day). Not proven first usage.
public enum SeatHistoryBoundOutcome: Sendable, Equatable, Hashable {
    case resolved(startDay: UsageDayKey)
    case unavailable
}

/// Typed All Time history bounds. Chart end is always the current UTC day at resolve time.
public struct AllTimeHistoryBounds: Sendable, Equatable, Hashable {
    public let endDay: UsageDayKey
    public let perSeat: [SeatID: SeatHistoryBoundOutcome]

    public init(endDay: UsageDayKey, perSeat: [SeatID: SeatHistoryBoundOutcome]) {
        self.endDay = endDay
        self.perSeat = perSeat
    }

    public var resolvedStarts: [SeatID: UsageDayKey] {
        var result: [SeatID: UsageDayKey] = [:]
        for (seatID, outcome) in perSeat {
            if case .resolved(let start) = outcome {
                result[seatID] = start
            }
        }
        return result
    }

    public var earliestResolvedStart: UsageDayKey? {
        resolvedStarts.values.min()
    }

    public var resolvedSeatCount: Int { resolvedStarts.count }

    public var requestedSeatCount: Int { perSeat.count }

    public var isPartial: Bool {
        requestedSeatCount > 0 && resolvedSeatCount < requestedSeatCount
    }

    public var hasAnyResolvedStart: Bool { resolvedSeatCount > 0 }

    public func start(for seatID: SeatID) -> UsageDayKey? {
        guard case .resolved(let start) = perSeat[seatID] else { return nil }
        return start
    }

    /// Chart window for the selected scope. End is always `endDay`.
    public func chartWindow(for scope: UsageScope) -> (start: UsageDayKey, end: UsageDayKey)? {
        switch scope {
        case .allAccounts:
            guard let start = earliestResolvedStart, start <= endDay else { return nil }
            return (start, endDay)
        case .account(let seatID):
            guard let start = self.start(for: seatID), start <= endDay else { return nil }
            return (start, endDay)
        }
    }

    /// Fetch clip start for one seat inside a chart window. Nil when that seat has no bound.
    public func fetchStart(for seatID: SeatID, chartStart: UsageDayKey) -> UsageDayKey? {
        guard let seatStart = start(for: seatID) else { return nil }
        return max(seatStart, chartStart)
    }

    public var boundCoverageCaption: String? {
        guard isPartial, requestedSeatCount > 0 else { return nil }
        return "Account age from \(resolvedSeatCount) of \(requestedSeatCount) accounts"
    }

    /// Recompute end to `today` while keeping per-seat starts.
    public func refreshingEnd(to today: UsageDayKey) -> AllTimeHistoryBounds {
        AllTimeHistoryBounds(endDay: today, perSeat: perSeat)
    }

    public static func resolve(
        outcomes: [SeatID: SeatHistoryBoundOutcome],
        today: UsageDayKey
    ) -> AllTimeHistoryBounds? {
        let bounds = AllTimeHistoryBounds(endDay: today, perSeat: outcomes)
        guard bounds.hasAnyResolvedStart else { return nil }
        return bounds
    }
}

/// Pure helper for parallel GetMe → bound outcomes (App wires the network).
public enum AllTimeHistoryBoundsResolver {
    public static let maxConcurrentLookups = 4

    public static func merge(
        seats: [SeatID],
        createdAtBySeat: [SeatID: Date?],
        failedSeats: Set<SeatID>,
        today: UsageDayKey
    ) -> AllTimeHistoryBounds? {
        var outcomes: [SeatID: SeatHistoryBoundOutcome] = [:]
        for seatID in seats {
            if failedSeats.contains(seatID) {
                outcomes[seatID] = .unavailable
                continue
            }
            if let created = createdAtBySeat[seatID], let date = created {
                let start = UsageDayKey.utcDay(containing: date)
                if start <= today {
                    outcomes[seatID] = .resolved(startDay: start)
                } else {
                    outcomes[seatID] = .unavailable
                }
            } else if createdAtBySeat[seatID] != nil {
                outcomes[seatID] = .unavailable
            } else {
                outcomes[seatID] = .unavailable
            }
        }
        return AllTimeHistoryBounds.resolve(outcomes: outcomes, today: today)
    }
}
