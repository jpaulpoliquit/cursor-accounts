@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class DashboardUsageSeriesWireTests: XCTestCase {
    func testGetMonthlyBillingCycleEmptyBodyAndDecimalStringBounds() async throws {
        nonisolated(unsafe) var seenBody: Data?
        nonisolated(unsafe) var headers: [String: String] = [:]
        let client = DashboardClient { request in
            seenBody = request.httpBody
            headers = request.allHTTPHeaderFields ?? [:]
            XCTAssertEqual(request.url?.lastPathComponent, "GetMonthlyBillingCycle")
            XCTAssertEqual(request.httpMethod, "POST")
            return try Self.ok(
                request,
                #"""
                {
                  "startDateEpochMillis": "1722470400000",
                  "endDateEpochMillis": "1725148800000"
                }
                """#
            )
        }
        let bounds = try await client.getMonthlyBillingCycle(access: Self.jwt)
        XCTAssertEqual(seenBody, Data("{}".utf8))
        XCTAssertEqual(headers["Authorization"], "Bearer \(Self.jwt.rawValue)")
        XCTAssertEqual(headers["Content-Type"], "application/json")
        XCTAssertEqual(headers["Connect-Protocol-Version"], "1")
        XCTAssertEqual(bounds.startMs, 1_722_470_400_000)
        XCTAssertEqual(bounds.endMs, 1_725_148_800_000)
    }

    func testGetMonthlyBillingCycleAcceptsNumericInt64() async throws {
        let client = DashboardClient { request in
            try Self.ok(
                request,
                #"{"startDateEpochMillis":1722470400000,"endDateEpochMillis":1725148800000}"#
            )
        }
        let bounds = try await client.getMonthlyBillingCycle(access: Self.jwt)
        XCTAssertEqual(bounds.startMs, 1_722_470_400_000)
        XCTAssertEqual(bounds.endMs, 1_725_148_800_000)
    }

    func testGetMonthlyBillingCycleMissingFieldsFailDecode() async throws {
        for json in [
            #"{"endDateEpochMillis":"1725148800000"}"#,
            #"{"startDateEpochMillis":"1722470400000"}"#,
            #"{"startDateEpochMillis":"nope","endDateEpochMillis":"1725148800000"}"#,
        ] {
            let client = DashboardClient { request in
                try Self.ok(request, json)
            }
            do {
                _ = try await client.getMonthlyBillingCycle(access: Self.jwt)
                XCTFail("expected decode failure for \(json)")
            } catch let error as DashboardClient.ClientError {
                XCTAssertEqual(error, .decode)
            }
        }
    }

    func testGetDailySpendByCategoryRequestBodyHeadersAndEnumEncoding() async throws {
        nonisolated(unsafe) var seenBody: Data?
        nonisolated(unsafe) var headers: [String: String] = [:]
        let client = DashboardClient { request in
            seenBody = request.httpBody
            headers = request.allHTTPHeaderFields ?? [:]
            XCTAssertEqual(request.url?.lastPathComponent, "GetDailySpendByCategory")
            return try Self.ok(request, #"{"dailySpend":[]}"#)
        }
        _ = try await client.getDailySpendByCategory(
            access: Self.jwt,
            periodStartMs: 1_722_470_400_000,
            periodEndMs: 1_725_148_800_000
        )
        let body = try XCTUnwrap(seenBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual((object["periodStartMs"] as? NSNumber)?.int64Value, 1_722_470_400_000)
        XCTAssertEqual((object["periodEndMs"] as? NSNumber)?.int64Value, 1_725_148_800_000)
        XCTAssertEqual(object["groupBy"] as? String, "MODEL")
        XCTAssertEqual(object["spendType"] as? String, "ALL")
        XCTAssertNil(object["teamId"])
        XCTAssertEqual(headers["Authorization"], "Bearer \(Self.jwt.rawValue)")
        XCTAssertEqual(headers["Content-Type"], "application/json")
        XCTAssertEqual(headers["Connect-Protocol-Version"], "1")
    }

    func testGetDailySpendByCategoryDecodesNumberAndStringInt64Rows() async throws {
        let client = DashboardClient { request in
            try Self.ok(
                request,
                #"""
                {
                  "dailySpend": [
                    {
                      "day": 1722470400000,
                      "category": "default",
                      "totalTokens": 100
                    },
                    {
                      "day": "1722556800000",
                      "category": "composer",
                      "totalTokens": "250",
                      "spendCents": "12"
                    }
                  ]
                }
                """#
            )
        }
        let rows = try await client.getDailySpendByCategory(
            access: Self.jwt,
            periodStartMs: 1,
            periodEndMs: 2
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].totalTokens, 100)
        XCTAssertNil(rows[0].spendCents)
        XCTAssertEqual(rows[0].day, UsageDayKey.utcDay(midnightMs: 1_722_470_400_000))
        XCTAssertEqual(rows[1].totalTokens, 250)
        XCTAssertEqual(rows[1].spendCents, 12)
        XCTAssertEqual(rows[1].day, UsageDayKey.utcDay(midnightMs: 1_722_556_800_000))
    }

    func testGetDailySpendByCategoryTokensOnlyAndSpendCentsRows() throws {
        let tokensOnly = try DashboardDailySpendWire.rows(from: GetDailySpendByCategoryWireDTO(
            dailySpend: [
                DailySpendByCategoryWireDTO(
                    day: FlexibleInt64(value: 1_722_470_400_000),
                    category: "a",
                    spendCents: nil,
                    totalTokens: FlexibleInt64(value: 9)
                ),
            ],
            categories: nil,
            effectiveLimitCents: nil
        ))
        XCTAssertEqual(tokensOnly.count, 1)
        XCTAssertNil(tokensOnly[0].spendCents)
        XCTAssertEqual(tokensOnly[0].totalTokens, 9)

        let withSpend = try DashboardDailySpendWire.rows(from: GetDailySpendByCategoryWireDTO(
            dailySpend: [
                DailySpendByCategoryWireDTO(
                    day: FlexibleInt64(value: 1_722_470_400_000),
                    category: "a",
                    spendCents: FlexibleInt32(value: 44),
                    totalTokens: FlexibleInt64(value: 3)
                ),
            ],
            categories: nil,
            effectiveLimitCents: nil
        ))
        XCTAssertEqual(withSpend[0].spendCents, 44)
        XCTAssertEqual(withSpend[0].totalTokens, 3)
    }

    func testGetDailySpendByCategoryInvalidOrMissingRowFieldsFail() async throws {
        for json in [
            #"{"dailySpend":[{"category":"a","totalTokens":1}]}"#,
            #"{"dailySpend":[{"day":1722470400000,"category":"a"}]}"#,
            #"{"dailySpend":[{"day":"bad","category":"a","totalTokens":1}]}"#,
        ] {
            let client = DashboardClient { request in
                try Self.ok(request, json)
            }
            do {
                _ = try await client.getDailySpendByCategory(
                    access: Self.jwt,
                    periodStartMs: 1,
                    periodEndMs: 2
                )
                XCTFail("expected decode failure for \(json)")
            } catch let error as DashboardClient.ClientError {
                XCTAssertEqual(error, .decode)
            }
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
}
