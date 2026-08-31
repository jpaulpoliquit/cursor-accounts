import Foundation

/// Menu / card usage hydration state for one signed-in seat.
public enum SeatUsageLoadState: Sendable, Equatable, Hashable {
    case unavailable
    case pending
    case failed
    case ready
}

extension SeatUsageLoadState {
    public static func resolve(
        auth: SeatAuthState,
        hasSnapshot: Bool,
        refreshPhase: UsageRefreshPhase,
        seatID: SeatID
    ) -> SeatUsageLoadState {
        switch auth {
        case .signedOut, .signingIn:
            return .unavailable
        case .signedIn, .needsReauth:
            break
        }
        if hasSnapshot {
            return .ready
        }
        switch refreshPhase {
        case .idle, .refreshing:
            return .pending
        case .settled(let report):
            switch report.outcomes[seatID] {
            case .failed:
                return .failed
            case .refreshed:
                return .ready
            case .skippedSignedOut:
                return .unavailable
            case nil:
                return .pending
            }
        }
    }
}
