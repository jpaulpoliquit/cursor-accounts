import Foundation

/// App-owned per-seat binding identity. Advanced synchronously before removal/rebind is observable.
@MainActor
public final class SeatBindingEpochRegistry {
    private var epochs: [SeatID: UInt64] = [:]

    public init() {}

    public func current(for seatID: SeatID) -> UInt64 {
        epochs[seatID] ?? 0
    }

    /// Bump identity before any async purge or new binding publish on this SeatID.
    @discardableResult
    public func advance(for seatID: SeatID) -> UInt64 {
        let next = (epochs[seatID] ?? 0) &+ 1
        epochs[seatID] = next
        return next
    }

    public func isCurrent(seatID: SeatID, epoch: UInt64) -> Bool {
        current(for: seatID) == epoch
    }

    public func snapshot(for seatIDs: some Sequence<SeatID>) -> [SeatID: UInt64] {
        Dictionary(uniqueKeysWithValues: seatIDs.map { ($0, current(for: $0)) })
    }
}
