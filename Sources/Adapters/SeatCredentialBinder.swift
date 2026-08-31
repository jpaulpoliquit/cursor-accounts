import CursorBarDomain
import Foundation

/// Keychain placement for hydrated credentials only. BindPolicy owns duplicates.
enum SeatCredentialBinder {
    static func placeTokens(
        preferredSeat: SeatID,
        tokens: AuthHTTPClient.SessionTokens,
        profile: HydratedAccountIdentity,
        apiKey: APIKey?,
        store: any SeatCredentialStore
    ) throws -> SeatID {
        let claims = JWTClaims.decode(jwt: tokens.access.rawValue)
        guard let identity = SessionIdentity.resolve(subject: claims?.subject, email: profile.email) else {
            throw AuthError.malformed(stage: .login)
        }
        let roster = try store.loadAll()
        if roster.contains(where: { $0.identity == identity }) {
            let decision = BindPolicy.decide(
                importedIdentity: identity,
                importedExpiresAt: claims?.expiresAt,
                roster: roster,
                storedProbeSucceeded: false
            )
            return try writeRecord(
                seatID: decision.seatID,
                identity: identity,
                tokens: tokens,
                profile: profile,
                apiKey: apiKey,
                expiresAt: claims?.expiresAt,
                roster: roster,
                store: store
            )
        }

        let seatID = roster.contains(where: { $0.seatID == preferredSeat })
            ? SeatID.next(occupied: roster.map(\.seatID))
            : preferredSeat
        return try writeRecord(
            seatID: seatID,
            identity: identity,
            tokens: tokens,
            profile: profile,
            apiKey: apiKey,
            expiresAt: claims?.expiresAt,
            roster: roster,
            store: store
        )
    }

    private static func writeRecord(
        seatID: SeatID,
        identity: SessionIdentity,
        tokens: AuthHTTPClient.SessionTokens,
        profile: HydratedAccountIdentity,
        apiKey: APIKey?,
        expiresAt: Date?,
        roster: [StoredSeatRecord],
        store: any SeatCredentialStore
    ) throws -> SeatID {
        let existing = roster.first(where: { $0.seatID == seatID })
        let record = StoredSeatRecord(
            seatID: seatID,
            identity: identity,
            access: tokens.access,
            refresh: tokens.refresh,
            email: profile.email ?? existing?.email,
            displayName: profile.displayName ?? existing?.displayName,
            expiresAt: expiresAt,
            membershipType: existing?.membershipType,
            subscriptionStatus: existing?.subscriptionStatus,
            apiKey: apiKey ?? existing?.apiKey
        )
        guard record.hasUsablePresentationIdentity else {
            throw AuthError.identityUnavailable
        }
        try store.save(record)
        return seatID
    }
}
