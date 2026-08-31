@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class AuthHTTPClientTests: XCTestCase {
    func testRefreshRequestExactBodyAndClientID() async throws {
        nonisolated(unsafe) var capturedBody: Data?
        nonisolated(unsafe) var capturedURL: URL?
        let client = AuthHTTPClient { request in
            capturedBody = request.httpBody
            capturedURL = request.url
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                Data(#"{"access_token":"new.access.jwt","refresh_token":"new.refresh.jwt"}"#.utf8),
                response
            )
        }
        let refresh = try XCTUnwrap(RefreshToken("old.refresh"))
        let tokens = try await client.refresh(refresh: refresh)
        XCTAssertEqual(capturedURL?.absoluteString, "https://api2.cursor.sh/oauth/token")
        let object = try JSONSerialization.jsonObject(with: XCTUnwrap(capturedBody)) as? [String: String]
        XCTAssertEqual(object?["grant_type"], "refresh_token")
        XCTAssertEqual(object?["client_id"], AuthClientConstants.oauthClientID)
        XCTAssertEqual(object?["client_id"], "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB")
        XCTAssertEqual(object?["refresh_token"], "old.refresh")
        XCTAssertEqual(tokens.access.rawValue, "new.access.jwt")
        XCTAssertEqual(tokens.refresh.rawValue, "new.refresh.jwt")
    }

    func testRefreshOmittingRefreshTokenUsesAccessAsRefresh() async throws {
        let client = AuthHTTPClient { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"access_token":"only.access.jwt"}"#.utf8), response)
        }
        let tokens = try await client.refresh(refresh: RefreshToken("prior")!)
        XCTAssertEqual(tokens.access.rawValue, "only.access.jwt")
        XCTAssertEqual(tokens.refresh.rawValue, "only.access.jwt")
    }

    func testExchangeAPIKeyExactRequest() async throws {
        nonisolated(unsafe) var authHeader: String?
        nonisolated(unsafe) var body: Data?
        nonisolated(unsafe) var method: String?
        let client = AuthHTTPClient { request in
            authHeader = request.value(forHTTPHeaderField: "Authorization")
            body = request.httpBody
            method = request.httpMethod
            XCTAssertEqual(request.url?.absoluteString, "https://api2.cursor.sh/auth/exchange_user_api_key")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (
                Data(#"{"accessToken":"ex.access.jwt","refreshToken":"ex.refresh.jwt"}"#.utf8),
                response
            )
        }
        let key = try XCTUnwrap(APIKey("crsr_test_key_material"))
        let tokens = try await client.exchangeAPIKey(key)
        XCTAssertEqual(method, "POST")
        XCTAssertEqual(authHeader, "Bearer crsr_test_key_material")
        XCTAssertEqual(body, Data("{}".utf8))
        XCTAssertEqual(tokens.access.rawValue, "ex.access.jwt")
        XCTAssertEqual(tokens.refresh.rawValue, "ex.refresh.jwt")
    }

    func testPoll403DeniedAndMalformed200() async {
        let denied = AuthHTTPClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        let deniedResult = await denied.poll(uuid: UUID(), verifier: "v")
        XCTAssertEqual(deniedResult, .denied)

        let malformed = AuthHTTPClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"accessToken":"only"}"#.utf8), response)
        }
        let malformedResult = await malformed.poll(uuid: UUID(), verifier: "v")
        XCTAssertEqual(malformedResult, .malformed)
    }

    func testAuthErrorOmitsSecrets() {
        let error = AuthError.http(stage: .refresh, status: 401)
        XCTAssertEqual(String(describing: error), "AuthError.http(stage: refresh, status: 401)")
        XCTAssertFalse(String(describing: error).contains("token"))
        XCTAssertFalse(String(reflecting: error).contains("crsr_"))
    }
}
