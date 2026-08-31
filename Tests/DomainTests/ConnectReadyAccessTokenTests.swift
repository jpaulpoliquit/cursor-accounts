import CursorBarDomain
import XCTest

final class ConnectReadyAccessTokenTests: XCTestCase {
    func testRejectsRawAPIKeyPrefix() throws {
        let key = try XCTUnwrap(AccessToken("crsr_abc"))
        XCTAssertNil(ConnectReadyAccessToken(key))
    }

    func testAcceptsJWTShapedAccessToken() throws {
        let access = try XCTUnwrap(AccessToken("header.payload.sig"))
        let ready = try XCTUnwrap(ConnectReadyAccessToken(access))
        XCTAssertEqual(ready.rawValue, "header.payload.sig")
        XCTAssertEqual(String(describing: ready), "<ConnectReadyAccessToken>")
    }
}
