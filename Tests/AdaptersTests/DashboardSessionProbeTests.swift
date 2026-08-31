@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class DashboardSessionProbeTests: XCTestCase {
    func testProbeSendsExpectedHeadersAndEmptyBody() async throws {
        let token = try XCTUnwrap(AccessToken(unsignedJWT(sub: "s", exp: 2_000_000_000)))
        nonisolated(unsafe) var seenMethod: String?
        nonisolated(unsafe) var seenPath: String?
        nonisolated(unsafe) var seenHeaders: [String: String] = [:]
        nonisolated(unsafe) var seenBody: Data?

        let probe = DashboardSessionProbe { request in
            seenMethod = request.httpMethod
            seenPath = request.url?.path
            if let fields = request.allHTTPHeaderFields {
                seenHeaders = fields
            }
            seenBody = request.httpBody
            let json = Data(
                #"""
                {
                  "billingCycleStart": "1700000000000",
                  "billingCycleEnd": "1800000000000",
                  "planUsage": {
                    "autoPercentUsed": 12.5,
                    "apiPercentUsed": 30,
                    "totalPercentUsed": 42.5
                  },
                  "displayMessage": "ok"
                }
                """#.utf8
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (json, response)
        }

        let result = await probe.probe(access: token)
        let period = try result.get()
        XCTAssertEqual(seenMethod, "POST")
        XCTAssertEqual(seenPath, "/aiserver.v1.DashboardService/GetCurrentPeriodUsage")
        XCTAssertEqual(seenHeaders["Content-Type"], "application/json")
        XCTAssertEqual(seenHeaders["Connect-Protocol-Version"], "1")
        XCTAssertEqual(seenHeaders["Authorization"], "Bearer \(token.rawValue)")
        XCTAssertEqual(seenBody, Data("{}".utf8))
        XCTAssertEqual(period.usage.autoPercentUsed.percent, 12.5, accuracy: 0.0001)
        XCTAssertEqual(period.usage.apiPercentUsed.percent, 30, accuracy: 0.0001)
        XCTAssertEqual(period.usage.totalPercentUsed.percent, 42.5, accuracy: 0.0001)
        XCTAssertEqual(period.usage.resetsAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(period.displayMessage, "ok")
    }

    func testMissingRequiredPercentIsDecodeFailureNotZero() throws {
        let json = Data(
            #"{"planUsage":{"autoPercentUsed":1,"apiPercentUsed":2},"billingCycleEnd":"1800000000000"}"#.utf8
        )
        XCTAssertThrowsError(try DashboardSessionProbe.parse(json)) { error in
            XCTAssertEqual(
                error as? DashboardWireCodec.DecodeError,
                .missingRequiredPercent("totalPercentUsed")
            )
        }
    }

    func testMissingPlanUsageIsDecodeFailure() {
        let json = Data(#"{"billingCycleEnd":"1800000000000","displayMessage":"x"}"#.utf8)
        XCTAssertThrowsError(try DashboardSessionProbe.parse(json))
    }

    func testSurfacedErrorsNeverContainRawToken() async throws {
        let secret = "header.payload.super-secret-probe-token"
        let token = try XCTUnwrap(AccessToken(secret))
        let probe = DashboardSessionProbe { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        let result = await probe.probe(access: token)
        guard case .failure(let failure) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertFalse(failure.surfaceMessage.contains(secret))
        XCTAssertFalse(String(describing: failure).contains(secret))
        XCTAssertFalse(String(reflecting: failure).contains(secret))
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
