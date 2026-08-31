import Foundation

/// Typed material imported from the active Cursor desktop session. Tokens stay out of snapshots.
public struct ImportedDesktopSession: Sendable, Equatable {
    public let access: AccessToken
    public let refresh: RefreshToken
    public let email: Email?
    public let displayName: DisplayName?
    public let membershipType: String?
    public let subscriptionStatus: String?
    public let claims: JWTClaims
    public let identity: SessionIdentity
    public let userDataDir: URL

    public init?(
        access: AccessToken,
        refresh: RefreshToken,
        email: Email?,
        displayName: DisplayName? = nil,
        membershipType: String?,
        subscriptionStatus: String?,
        userDataDir: URL
    ) {
        guard let claims = JWTClaims.decode(jwt: access.rawValue) else { return nil }
        guard let identity = SessionIdentity.resolve(subject: claims.subject, email: email) else {
            return nil
        }
        self.access = access
        self.refresh = refresh
        self.email = email
        self.displayName = displayName
        self.membershipType = membershipType
        self.subscriptionStatus = subscriptionStatus
        self.claims = claims
        self.identity = identity
        self.userDataDir = userDataDir
    }
}

extension ImportedDesktopSession: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "ImportedDesktopSession(identity: \(identity), email: \(email?.value ?? "nil"))"
    }

    public var debugDescription: String { description }
}
