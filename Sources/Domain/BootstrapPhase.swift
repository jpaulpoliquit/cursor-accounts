import Foundation

/// Launch/bootstrap lifecycle. Avoids scattered isLoading/hasError booleans.
public enum BootstrapPhase: Sendable, Equatable {
    case pending
    case running
    case settled(BootstrapOutcome)
}

public enum BootstrapOutcome: Sendable, Equatable {
    case imported(SeatID)
    case refreshed(SeatID)
    case kept(SeatID)
    case noDesktopSession
    case importFailed(message: String)

    public var inlineAuthDetail: String? {
        switch self {
        case .importFailed(let message):
            return message
        case .imported, .refreshed, .kept, .noDesktopSession:
            return nil
        }
    }
}
