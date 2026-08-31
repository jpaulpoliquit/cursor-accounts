@testable import CursorBarAdapters
import XCTest

final class PKCETests: XCTestCase {
    func testKnownVectorAndBase64URLHasNoPadding() {
        let raw = Data(0..<32)
        let verifier = PKCE.base64URLEncode(raw)
        XCTAssertEqual(verifier, "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
        XCTAssertFalse(verifier.contains("="))
        XCTAssertFalse(verifier.contains("+"))
        XCTAssertFalse(verifier.contains("/"))

        let challenge = PKCE.challenge(forVerifier: verifier)
        XCTAssertEqual(challenge, "6oZqdX5MOLq_qBJ8vppAnT4fk6AP8UiP9zX8-Rev_9A")
        XCTAssertFalse(challenge.contains("="))
    }

    func testDeepControlURLExactQueryFields() {
        let uuid = UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!
        let url = PKCE.deepControlLoginURL(challenge: "chal", uuid: uuid)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "cursor.com")
        XCTAssertEqual(components.path, "/loginDeepControl")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["challenge"], "chal")
        XCTAssertEqual(items["uuid"], "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(items["mode"], "login")
        XCTAssertEqual(items["redirectTarget"], "cli")
        XCTAssertEqual(items.count, 4)
    }
}
