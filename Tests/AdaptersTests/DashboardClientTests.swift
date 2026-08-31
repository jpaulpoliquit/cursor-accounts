@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class DashboardClientTests: XCTestCase {
    func testRawCrsrCannotBecomeConnectReadyAccessToken() throws {
        let token = try XCTUnwrap(AccessToken("crsr_live_forbidden"))
        XCTAssertNil(ConnectReadyAccessToken(token))
        XCTAssertNil(ConnectReadyAccessToken(validatedJWT: "crsr_live_forbidden"))
    }

    func testGetPlanInfoParsesIncludedCentsAndPrice() async throws {
        let client = DashboardClient { request in
            XCTAssertEqual(request.url?.lastPathComponent, "GetPlanInfo")
            XCTAssertEqual(request.httpBody, Data("{}".utf8))
            return try Self.ok(
                request,
                #"""
                {
                  "planInfo": {
                    "planName": "ultra",
                    "includedAmountCents": 20000,
                    "price": "$200/mo",
                    "billingCycleEnd": "1800000000000",
                    "planOwner": "personal"
                  }
                }
                """#
            )
        }
        let plan = try await client.getPlanInfo(access: Self.jwt)
        XCTAssertEqual(plan.name, "ultra")
        XCTAssertEqual(plan.includedAmountCents?.cents, 20_000)
        XCTAssertEqual(plan.price, "$200/mo")
        XCTAssertEqual(plan.billingCycleEnd, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(plan.planOwner, .personal)
    }

    func testGetCurrentPeriodUsageSeparatesAutoApiTotalAndOpaqueSpend() async throws {
        let client = DashboardClient { request in
            XCTAssertEqual(request.url?.lastPathComponent, "GetCurrentPeriodUsage")
            return try Self.ok(
                request,
                #"""
                {
                  "billingCycleStart": "1700000000000",
                  "billingCycleEnd": "1800000000000",
                  "planUsage": {
                    "autoPercentUsed": 11,
                    "apiPercentUsed": 22,
                    "totalPercentUsed": 33
                  },
                  "spendLimitUsage": {
                    "individualUsed": 1500,
                    "individualLimit": 4000
                  },
                  "displayMessage": "You've used all of your included usage",
                  "autoModelSelectedDisplayMessage": "auto msg",
                  "namedModelSelectedDisplayMessage": "api msg"
                }
                """#
            )
        }
        let detail = try await client.getCurrentPeriodUsage(access: Self.jwt)
        XCTAssertEqual(detail.usage.autoPercentUsed.percent, 11, accuracy: 0.0001)
        XCTAssertEqual(detail.usage.apiPercentUsed.percent, 22, accuracy: 0.0001)
        XCTAssertEqual(detail.usage.totalPercentUsed.percent, 33, accuracy: 0.0001)
        XCTAssertEqual(detail.spendLimitUsage?.individualUsed?.cents, 1500)
        XCTAssertEqual(detail.spendLimitUsage?.individualLimit?.cents, 4000)
        XCTAssertEqual(detail.displayMessage, "You've used all of your included usage")
        XCTAssertEqual(detail.autoPercentDisplayMessage, "auto msg")
        XCTAssertEqual(detail.apiPercentDisplayMessage, "api msg")
    }

    func testSpendLimitUnitsAcceptDecimalStringsToo() async throws {
        let client = DashboardClient { request in
            try Self.ok(
                request,
                #"""
                {
                  "planUsage":{"autoPercentUsed":1,"apiPercentUsed":2,"totalPercentUsed":3},
                  "spendLimitUsage":{"individualUsed":"12620","individualLimit":"19000","totalSpend":999999}
                }
                """#
            )
        }
        let detail = try await client.getCurrentPeriodUsage(access: Self.jwt)
        XCTAssertEqual(detail.spendLimitUsage?.individualUsed?.cents, 12_620)
        XCTAssertEqual(detail.spendLimitUsage?.individualLimit?.cents, 19_000)
        // planUsage.totalSpend / spendLimitUsage.totalSpend must not drive personal used.
        XCTAssertNotEqual(detail.spendLimitUsage?.individualUsed?.cents, 999_999)
    }

    func testInt64DecimalParsingForCreditsAndPolicy() async throws {
        let client = DashboardClient { request in
            switch request.url?.lastPathComponent {
            case "GetCreditGrantsBalance":
                return try Self.ok(
                    request,
                    #"""
                    {
                      "creditBalanceCents": "1234",
                      "totalCents": "5000",
                      "usedCents": "3766"
                    }
                    """#
                )
            case "GetUsageLimitPolicyStatus":
                return try Self.ok(
                    request,
                    #"""
                    {
                      "canConfigureSpendLimit": true,
                      "canAdjustOnDemand": true,
                      "recommendedLimitCents": "400000",
                      "minLimitCents": "0",
                      "maxLimitCents": "1000000",
                      "currentLimitCents": "200000"
                    }
                    """#
                )
            default:
                throw URLError(.badURL)
            }
        }
        let credits = try await client.getCreditGrantsBalance(access: Self.jwt)
        guard case let .present(balance, total, used) = credits else {
            return XCTFail("expected present credits")
        }
        XCTAssertEqual(balance.cents, 1234)
        XCTAssertEqual(total.cents, 5000)
        XCTAssertEqual(used.cents, 3766)

        let policy = try await client.getUsageLimitPolicyStatus(access: Self.jwt)
        XCTAssertEqual(policy.canConfigureSpendLimit, true)
        XCTAssertEqual(policy.recommendedLimitCents?.cents, 400_000)
        XCTAssertEqual(policy.currentLimitCents?.cents, 200_000)
        XCTAssertTrue(policy.allowsOnDemandAdjust)
    }

    func testEmptyCreditsObjectIsAbsentNotSilentZero() async throws {
        let client = DashboardClient { request in
            try Self.ok(request, "{}")
        }
        let credits = try await client.getCreditGrantsBalance(access: Self.jwt)
        XCTAssertEqual(credits, .absent)
    }

    func testSparsePolicyAllowed() async throws {
        let client = DashboardClient { request in
            try Self.ok(request, #"{"canAdjustOnDemand":false}"#)
        }
        let policy = try await client.getUsageLimitPolicyStatus(access: Self.jwt)
        XCTAssertEqual(policy.canAdjustOnDemand, false)
        XCTAssertNil(policy.recommendedLimitCents)
        XCTAssertFalse(policy.allowsOnDemandAdjust)
    }

    func testHardLimitReadModes() async throws {
        let cases: [(String, HardLimit)] = [
            (#"{"noUsageBasedAllowed":true,"hardLimit":0}"#, .off),
            (#"{"noUsageBasedAllowed":false,"hardLimit":40}"#, .fixed(PositiveDollars(40)!)),
            (#"{"noUsageBasedAllowed":false,"hardLimit":2147483647}"#, .unlimited),
        ]
        for (json, expected) in cases {
            let client = DashboardClient { request in
                try Self.ok(request, json)
            }
            let limit = try await client.getHardLimit(access: Self.jwt)
            XCTAssertEqual(limit, expected)
        }
    }

    func testHardLimitInvalidStateErrors() async throws {
        let client = DashboardClient { request in
            try Self.ok(request, #"{"noUsageBasedAllowed":false,"hardLimit":0}"#)
        }
        do {
            _ = try await client.getHardLimit(access: Self.jwt)
            XCTFail("expected invalid hard limit")
        } catch let error as DashboardClient.ClientError {
            XCTAssertEqual(error, .invalidHardLimit)
        }
    }

    func testSetHardLimitWriteBodies() async throws {
        let modes: [(OnDemandMode, String)] = [
            (.off, #"{"hardLimit":0,"noUsageBasedAllowed":true}"#),
            (.fixed(PositiveDollars(25)!), #"{"hardLimit":25,"noUsageBasedAllowed":false}"#),
            (.unlimited, #"{"hardLimit":2147483647,"noUsageBasedAllowed":false}"#),
        ]
        for (mode, expectedJSON) in modes {
            nonisolated(unsafe) var body: Data?
            let client = DashboardClient { request in
                body = request.httpBody
                XCTAssertEqual(request.url?.lastPathComponent, "SetHardLimit")
                return try Self.ok(request, "{}")
            }
            try await client.setHardLimit(access: Self.jwt, mode: mode)
            let seen = try XCTUnwrap(body)
            let expected = try XCTUnwrap(expectedJSON.data(using: .utf8))
            XCTAssertEqual(
                try JSONSerialization.jsonObject(with: seen) as? NSDictionary,
                try JSONSerialization.jsonObject(with: expected) as? NSDictionary
            )
        }
    }

    func testHeadersOnEveryMethod() async throws {
        let methods = [
            "GetPlanInfo",
            "GetCurrentPeriodUsage",
            "GetHardLimit",
            "GetCreditGrantsBalance",
            "GetUsageLimitPolicyStatus",
        ]
        for method in methods {
            nonisolated(unsafe) var headers: [String: String] = [:]
            let client = DashboardClient { request in
                headers = request.allHTTPHeaderFields ?? [:]
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.lastPathComponent, method)
                return try Self.fixture(for: method, request: request)
            }
            _ = try await Self.invoke(client, method: method)
            XCTAssertEqual(headers["Authorization"], "Bearer \(Self.jwt.rawValue)")
            XCTAssertEqual(headers["Content-Type"], "application/json")
            XCTAssertEqual(headers["Connect-Protocol-Version"], "1")
        }
    }

    private static var jwt: ConnectReadyAccessToken {
        ConnectReadyAccessToken(validatedJWT: "header.payload.signature")!
    }

    private static func ok(_ request: URLRequest, _ json: String) throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(json.utf8), response)
    }

    private static func fixture(for method: String, request: URLRequest) throws -> (Data, URLResponse) {
        switch method {
        case "GetPlanInfo":
            return try ok(request, #"{"planInfo":{"planName":"ultra","includedAmountCents":1}}"#)
        case "GetCurrentPeriodUsage":
            return try ok(
                request,
                #"{"planUsage":{"autoPercentUsed":1,"apiPercentUsed":2,"totalPercentUsed":3}}"#
            )
        case "GetHardLimit":
            return try ok(request, #"{"noUsageBasedAllowed":true,"hardLimit":0}"#)
        case "GetCreditGrantsBalance":
            return try ok(request, "{}")
        case "GetUsageLimitPolicyStatus":
            return try ok(request, "{}")
        default:
            throw URLError(.badURL)
        }
    }

    private static func invoke(_ client: DashboardClient, method: String) async throws {
        switch method {
        case "GetPlanInfo":
            _ = try await client.getPlanInfo(access: jwt)
        case "GetCurrentPeriodUsage":
            _ = try await client.getCurrentPeriodUsage(access: jwt)
        case "GetHardLimit":
            _ = try await client.getHardLimit(access: jwt)
        case "GetCreditGrantsBalance":
            _ = try await client.getCreditGrantsBalance(access: jwt)
        case "GetUsageLimitPolicyStatus":
            _ = try await client.getUsageLimitPolicyStatus(access: jwt)
        default:
            throw URLError(.badURL)
        }
    }
}
