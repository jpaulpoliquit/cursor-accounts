import CursorBarDomain
import Foundation

/// How in-flight permits are partitioned.
public enum FetchIsolation: Sendable, Equatable {
    /// One shared lane. Used by tests and single-budget work.
    case shared
    /// Independent lane per seat. DashboardService limits are per account JWT.
    case perSeat
}

/// Bounded in-flight gate. Production usage refreshers share one per-seat instance.
public actor FetchConcurrencyGate {
    public static let defaultLimit = 5
    /// Concurrent RPCs allowed on one account. Seats do not wait on each other.
    public static let defaultPerSeatLimit = 3

    private struct Lane {
        var inFlight = 0
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let limit: Int
    private let isolation: FetchIsolation
    private var sharedLane = Lane()
    private var seatLanes: [SeatID: Lane] = [:]
    private var observedMax = 0

    public init(
        limit: Int = FetchConcurrencyGate.defaultLimit,
        isolation: FetchIsolation = .shared
    ) {
        precondition(limit > 0)
        self.limit = limit
        self.isolation = isolation
    }

    public var currentInFlight: Int { totalInFlight }
    public var maxObservedInFlight: Int { observedMax }

    public func withPermit<T: Sendable>(
        seatID: SeatID? = nil,
        _ operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        let key = laneKey(seatID)
        await acquire(key)
        do {
            let result = try await operation()
            release(key)
            return result
        } catch {
            release(key)
            throw error
        }
    }

    private func laneKey(_ seatID: SeatID?) -> SeatID? {
        switch isolation {
        case .shared:
            return nil
        case .perSeat:
            return seatID
        }
    }

    private var totalInFlight: Int {
        sharedLane.inFlight + seatLanes.values.reduce(0) { $0 + $1.inFlight }
    }

    private func lane(_ key: SeatID?) -> Lane {
        guard let key else { return sharedLane }
        return seatLanes[key] ?? Lane()
    }

    private func store(_ key: SeatID?, _ lane: Lane) {
        if let key {
            seatLanes[key] = lane
        } else {
            sharedLane = lane
        }
    }

    private func acquire(_ key: SeatID?) async {
        var current = lane(key)
        if current.inFlight < limit {
            current.inFlight += 1
            store(key, current)
            observedMax = max(observedMax, totalInFlight)
            return
        }
        await withCheckedContinuation { continuation in
            var waiting = lane(key)
            waiting.waiters.append(continuation)
            store(key, waiting)
        }
    }

    private func release(_ key: SeatID?) {
        var current = lane(key)
        if current.waiters.isEmpty {
            current.inFlight -= 1
            store(key, current)
        } else {
            let next = current.waiters.removeFirst()
            store(key, current)
            next.resume()
        }
    }
}
