import Foundation

public struct SeatSnapshot: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: SeatID { seatID }

    public let seatID: SeatID
    public let auth: SeatAuthState
    public let email: Email?
    public let displayName: DisplayName?
    /// Cursor profile photo when the desktop session or Keychain row still has it.
    public let pictureURL: URL?
    public let plan: PlanInfo?
    public let usage: PeriodUsage?
    public let onDemand: OnDemandState?
    /// Secret-free inline message for auth/bootstrap failures. Never holds credentials.
    public let authDetail: String?

    public init(
        seatID: SeatID,
        auth: SeatAuthState,
        email: Email? = nil,
        displayName: DisplayName? = nil,
        pictureURL: URL? = nil,
        plan: PlanInfo? = nil,
        usage: PeriodUsage? = nil,
        onDemand: OnDemandState? = nil,
        authDetail: String? = nil
    ) {
        self.seatID = seatID
        self.auth = auth
        self.email = email
        self.displayName = displayName
        self.pictureURL = pictureURL
        self.plan = plan
        self.usage = usage
        self.onDemand = onDemand
        self.authDetail = authDetail
    }

    public var statusPill: SeatStatusPill? {
        guard let usage, let onDemand else { return nil }
        let included = SeatStatusPill.includedPool(usage: usage, displayMessage: nil)
        let spend: SeatStatusPill.Input.OnDemandSpend =
            onDemand.isConsuming ? .consuming : .idle
        return SeatStatusPill.derive(
            .init(included: included, mode: onDemand.mode, spend: spend)
        )
    }

    public static func empty(seatID: SeatID) -> SeatSnapshot {
        SeatSnapshot(seatID: seatID, auth: .signedOut)
    }

    /// Email or display name present. Subject-only Keychain rows are not connected.
    public var hasUsableIdentity: Bool {
        email != nil || displayName != nil
    }
}

/// Roster-wide view. Only connected or in-flight accounts.
public struct AggregateSnapshot: Codable, Sendable, Equatable, Hashable {
    public let seats: [SeatSnapshot]

    public init(seats: [SeatSnapshot]) {
        var byID: [SeatID: SeatSnapshot] = [:]
        for seat in seats {
            byID[seat.seatID] = seat
        }
        self.seats = byID.values.sorted { $0.seatID < $1.seatID }
    }

    public static var empty: AggregateSnapshot {
        AggregateSnapshot(seats: [])
    }

    public var signedInCount: Int {
        seats.reduce(0) { count, seat in
            switch seat.auth {
            case .signedIn, .needsReauth:
                return count + (seat.hasUsableIdentity ? 1 : 0)
            case .signedOut, .signingIn:
                return count
            }
        }
    }

    public var menuBarLabel: String {
        ProductName.display
    }
}
