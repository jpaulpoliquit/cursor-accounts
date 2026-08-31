import CursorBarDomain
import XCTest

final class CursorIDEIdentityTests: XCTestCase {
    func testVerificationRequiresExpectedSubject() {
        let identity = CursorIDEIdentity(subject: "auth0|a", email: Email("a@example.com"))
        XCTAssertTrue(CursorIDEIdentity.verify(observed: identity, expectedSubject: "auth0|a"))
        XCTAssertFalse(CursorIDEIdentity.verify(observed: identity, expectedSubject: "auth0|b"))
        XCTAssertFalse(CursorIDEIdentity.verify(observed: identity, expectedSubject: "   "))
    }

    func testMatcherPrefersSubjectAndReturnsNilOnAmbiguity() throws {
        let access = try XCTUnwrap(AccessToken(unsignedJWT(sub: "shared-sub", exp: 1)))
        let refresh = try XCTUnwrap(RefreshToken(unsignedJWT(sub: "shared-sub", exp: 1)))
        let seat1 = StoredSeatRecord(
            seatID: .seat1,
            identity: .subject("auth0|one"),
            access: access,
            refresh: refresh,
            email: Email("one@example.com"),
            expiresAt: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )
        let seat2 = StoredSeatRecord(
            seatID: .seat2,
            identity: .subject("auth0|two"),
            access: access,
            refresh: refresh,
            email: Email("two@example.com"),
            expiresAt: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )
        let fallbackEmail = try XCTUnwrap(Email("fallback@example.com"))
        let seat3 = StoredSeatRecord(
            seatID: .seat3,
            identity: .email(fallbackEmail),
            access: access,
            refresh: refresh,
            email: fallbackEmail,
            expiresAt: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )

        let bySubject = CursorIDEIdentity(subject: "auth0|two", email: Email("ignored@example.com"))
        XCTAssertEqual(
            CursorIDEIdentityMatcher.matchingSeat(identity: bySubject, roster: [seat1, seat2, seat3]),
            .seat2
        )

        let byEmail = CursorIDEIdentity(subject: "unknown-sub", email: Email("Fallback@example.com"))
        XCTAssertEqual(
            CursorIDEIdentityMatcher.matchingSeat(identity: byEmail, roster: [seat1, seat2, seat3]),
            .seat3
        )

        let duplicateSubject = StoredSeatRecord(
            seatID: .seat4,
            identity: .subject("auth0|one"),
            access: access,
            refresh: refresh,
            email: Email("dup@example.com"),
            expiresAt: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )
        XCTAssertNil(
            CursorIDEIdentityMatcher.matchingSeat(
                identity: CursorIDEIdentity(subject: "auth0|one", email: nil),
                roster: [seat1, duplicateSubject]
            )
        )

        let duplicateEmail = StoredSeatRecord(
            seatID: .seat5,
            identity: .email(fallbackEmail),
            access: access,
            refresh: refresh,
            email: fallbackEmail,
            expiresAt: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )
        XCTAssertNil(
            CursorIDEIdentityMatcher.matchingSeat(
                identity: CursorIDEIdentity(subject: "nope", email: Email("fallback@example.com")),
                roster: [seat3, duplicateEmail]
            )
        )
    }

    func testFromAccessTokenRequiresSubject() {
        let jwt = unsignedJWT(sub: "auth0|x", exp: 1_800_000_000)
        let identity = CursorIDEIdentity.from(accessTokenJWT: jwt, cachedEmail: "x@example.com")
        XCTAssertEqual(identity?.subject, "auth0|x")
        XCTAssertEqual(identity?.email?.value, "x@example.com")
        XCTAssertNil(CursorIDEIdentity.from(accessTokenJWT: "not-jwt", cachedEmail: "x@example.com"))
        XCTAssertFalse(String(describing: identity!).contains(jwt))
    }

    private func unsignedJWT(sub: String, exp: Int) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URL()
        let payload = Data(#"{"sub":"\#(sub)","exp":\#(exp)}"#.utf8).base64URL()
        return "\(header).\(payload).sig"
    }
}

private extension Data {
    func base64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
