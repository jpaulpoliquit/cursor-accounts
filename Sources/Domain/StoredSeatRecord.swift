import Foundation

/// Keychain-backed seat credentials for `app.cursorbar` only. Never persisted into UI snapshots.
public struct StoredSeatRecord: Sendable, Equatable {
    public let seatID: SeatID
    public let identity: SessionIdentity
    public let access: AccessToken
    public let refresh: RefreshToken
    public let email: Email?
    public let displayName: DisplayName?
    public let pictureURL: URL?
    public let expiresAt: Date?
    public let membershipType: String?
    public let subscriptionStatus: String?
    /// Optional long-lived `crsr_` key. Never passed to DashboardClient.
    public let apiKey: APIKey?

    public init(
        seatID: SeatID,
        identity: SessionIdentity,
        access: AccessToken,
        refresh: RefreshToken,
        email: Email?,
        displayName: DisplayName? = nil,
        pictureURL: URL? = nil,
        expiresAt: Date?,
        membershipType: String?,
        subscriptionStatus: String?,
        apiKey: APIKey? = nil
    ) {
        self.seatID = seatID
        self.identity = identity
        self.access = access
        self.refresh = refresh
        self.email = email
        self.displayName = displayName
        self.pictureURL = pictureURL
        self.expiresAt = expiresAt
        self.membershipType = membershipType
        self.subscriptionStatus = subscriptionStatus
        self.apiKey = apiKey
    }

    public func publicSnapshot(usage: PeriodUsage? = nil, authDetail: String? = nil) -> SeatSnapshot {
        let auth: SeatAuthState = authDetail == nil ? .signedIn : .needsReauth
        let plan: PlanInfo? = membershipType.map { PlanInfo(name: $0) }
        return SeatSnapshot(
            seatID: seatID,
            auth: auth,
            email: email,
            displayName: displayName,
            pictureURL: pictureURL,
            plan: plan,
            usage: usage,
            onDemand: nil,
            authDetail: authDetail
        )
    }
}

extension StoredSeatRecord: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "StoredSeatRecord(seat: \(seatID.rawValue), identity: \(identity))"
    }

    public var debugDescription: String { description }
}
