import Foundation

/// Single connect CTA / in-progress add-account chrome. Views never invent empty seat rows.
public enum AddAccountPresentation: Sendable, Equatable, Hashable {
    case available(title: String, seatID: SeatID)
    case signingIn(seatID: SeatID, canCancel: Bool, isFinishing: Bool)
    case failed(title: String, seatID: SeatID, message: String)

    public var menuTitle: String {
        switch self {
        case .available(let title, _), .failed(let title, _, _):
            return title
        case .signingIn(_, _, let isFinishing):
            return isFinishing ? "Finishing sign-in…" : "Signing in…"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .available(let title, _):
            if title == "Connect another account" {
                return "Connect another Cursor account"
            }
            return title
        case .failed(let title, _, let message):
            return "\(title). \(message)"
        case .signingIn(_, _, let isFinishing):
            return isFinishing
                ? "Finishing Cursor account sign-in"
                : "Signing in to Cursor account"
        }
    }

    public var targetSeatID: SeatID? {
        switch self {
        case .available(_, let seatID), .signingIn(let seatID, _, _), .failed(_, let seatID, _):
            return seatID
        }
    }

    /// Next unused account key. Shared by projector and AppModel.
    public static func firstAvailableSeatID(in seats: [SeatPresentation]) -> SeatID {
        let occupied = Set(seats.compactMap { seat -> SeatID? in
            if seat.loginPhase.failure != nil {
                return seat.seatID
            }
            switch seat.auth {
            case .signedOut:
                return seat.loginPhase.isInFlight ? seat.seatID : nil
            case .signingIn, .signedIn, .needsReauth:
                return seat.seatID
            }
        })
        return SeatID.next(occupied: occupied)
    }

    public static func project(from seats: [SeatPresentation]) -> AddAccountPresentation {
        if let inflight = seats.first(where: { seat in
            seat.auth == .signingIn && !isConnectedAccount(seat)
        }) {
            let finishing: Bool
            if case .finishingSignIn = inflight.loginPhase {
                finishing = true
            } else {
                finishing = false
            }
            return .signingIn(
                seatID: inflight.seatID,
                canCancel: inflight.loginPhase.isInFlight,
                isFinishing: finishing
            )
        }

        let connectedCount = seats.filter(isConnectedAccount).count
        let seatID = firstAvailableSeatID(in: seats)
        let title = connectedCount == 0 ? "Connect Cursor account" : "Connect another account"
        if let failure = seats.compactMap(\.loginPhase.failure).first {
            return .failed(title: title, seatID: seatID, message: failure.surfaceMessage)
        }
        return .available(title: title, seatID: seatID)
    }

    public static func isConnectedAccount(_ seat: SeatPresentation) -> Bool {
        switch seat.auth {
        case .signedIn, .needsReauth:
            // Usage/plan paint must not make a subject-only ghost look connected.
            return seat.hasUsableIdentity
        case .signedOut, .signingIn:
            return false
        }
    }
}
