@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class SeatCredentialBinderTests: XCTestCase {
    func testOccupiedPreferredSeatPlacesOnNextEmpty() throws {
        let existing = StoredSeatRecord(
            seatID: .seat1,
            identity: .subject("already-there"),
            access: try XCTUnwrap(AccessToken("old.access.jwt")),
            refresh: try XCTUnwrap(RefreshToken("old.refresh")),
            email: Email("kept@example.com"),
            displayName: DisplayName("kept"),
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
            membershipType: nil,
            subscriptionStatus: nil
        )
        let store = UncheckedMemorySeatStore(records: [existing])
        let jwt = unsignedJWT(sub: "new-user", exp: 2_000_000_000)
        let tokens = AuthHTTPClient.SessionTokens(
            access: try XCTUnwrap(AccessToken(jwt)),
            refresh: try XCTUnwrap(RefreshToken("new.refresh"))
        )
        let profile = try XCTUnwrap(
            HydratedAccountIdentity(email: Email("new@example.com"), displayName: DisplayName("new"))
        )
        let placed = try SeatCredentialBinder.placeTokens(
            preferredSeat: .seat1,
            tokens: tokens,
            profile: profile,
            apiKey: nil,
            store: store
        )
        XCTAssertEqual(placed, .seat2)
        XCTAssertNotNil(try store.load(seatID: .seat1))
        XCTAssertEqual(try store.load(seatID: .seat2)?.identity, .subject("new-user"))
        XCTAssertEqual(try store.loadAll().count, 2)
    }
}

private func unsignedJWT(sub: String, exp: Int) -> String {
    let header = Data(#"{"alg":"none"}"#.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    let payload = Data(#"{"sub":"\#(sub)","exp":\#(exp)}"#.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "\(header).\(payload).sig"
}
