import CursorBarDomain
import XCTest

final class JWTClaimsTests: XCTestCase {
    func testDecodeReadsSubAndExpWithoutVerifyingSignature() throws {
        let payload = #"{"sub":"abc-123","exp":1700000000}"#
        let jwt = makeUnsignedJWT(payloadJSON: payload)
        let claims = try XCTUnwrap(JWTClaims.decode(jwt: jwt))
        XCTAssertEqual(claims.subject, "abc-123")
        XCTAssertEqual(claims.expiresAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(claims.pictureURL)
    }

    func testDecodeReadsHTTPSPicture() throws {
        let payload = #"{"sub":"abc-123","picture":"https://example.com/me.png"}"#
        let jwt = makeUnsignedJWT(payloadJSON: payload)
        let claims = try XCTUnwrap(JWTClaims.decode(jwt: jwt))
        XCTAssertEqual(claims.pictureURL?.absoluteString, "https://example.com/me.png")
    }

    func testIdentityPrefersSubjectOverEmail() throws {
        let email = try XCTUnwrap(Email("a@example.com"))
        let identity = try XCTUnwrap(SessionIdentity.resolve(subject: "sub-1", email: email))
        XCTAssertEqual(identity, .subject("sub-1"))
    }

    func testIdentityFallsBackToEmail() throws {
        let email = try XCTUnwrap(Email("a@example.com"))
        let identity = try XCTUnwrap(SessionIdentity.resolve(subject: "  ", email: email))
        XCTAssertEqual(identity, .email(email))
    }

    private func makeUnsignedJWT(payloadJSON: String) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncodedString()
        let payload = Data(payloadJSON.utf8).base64URLEncodedString()
        return "\(header).\(payload).sig"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
