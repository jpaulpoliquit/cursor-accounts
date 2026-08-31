import Foundation

/// Aggregate menu attention. Higher rawValue wins when picking the worst seat signal.
public enum MenuAttention: Int, Sendable, Equatable, Comparable, Hashable {
    case countOnly = 0
    case onDemandReady = 1
    case exhausted = 2
    case onDemandActive = 3
    case needsReauth = 4

    public static func < (lhs: MenuAttention, rhs: MenuAttention) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func from(auth: SeatAuthState, pill: SeatStatusPill?) -> MenuAttention {
        switch auth {
        case .needsReauth:
            return .needsReauth
        case .signedOut, .signingIn, .signedIn:
            break
        }
        guard let pill else { return .countOnly }
        switch pill {
        case .onDemandActive:
            return .onDemandActive
        case .exhausted:
            return .exhausted
        case .onDemandReady:
            return .onDemandReady
        }
    }

    public static func worst(among seats: [(auth: SeatAuthState, pill: SeatStatusPill?)]) -> MenuAttention {
        seats.reduce(.countOnly) { current, seat in
            max(current, from(auth: seat.auth, pill: seat.pill))
        }
    }

    public var shortTitle: String {
        switch self {
        case .countOnly:
            return ""
        case .onDemandReady:
            return "Ready"
        case .exhausted:
            return "Exhausted"
        case .onDemandActive:
            return "On-demand"
        case .needsReauth:
            return "Reauth"
        }
    }
}
