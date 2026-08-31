@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class DashboardAggregatedUsageWireTests: XCTestCase {
    func testRequestOmitsTeamAndUserAndUsesExplicitDates() async throws {
        nonisolated(unsafe) var seenBody: Data?
        nonisolated(unsafe) var headers: [String: String] = [:]
        let client = DashboardClient { request in
            seenBody = request.httpBody
            headers = request.allHTTPHeaderFields ?? [:]
            XCTAssertEqual(request.url?.lastPathComponent, "GetAggregatedUsageEvents")
            return try Self.ok(request, #"{"totalInputTokens":0,"totalOutputTokens":0,"totalCacheWriteTokens":0,"totalCacheReadTokens":0,"aggregations":[]}"#)
        }
        _ = try await client.getAggregatedUsageEvents(
            access: Self.jwt,
            startDateMs: 1_722_470_400_000,
            endDateMs: 1_725_148_800_000,
            seatID: .seat1
        )
        let body = try XCTUnwrap(seenBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual((object["startDate"] as? NSNumber)?.int64Value, 1_722_470_400_000)
        XCTAssertEqual((object["endDate"] as? NSNumber)?.int64Value, 1_725_148_800_000)
        XCTAssertNil(object["teamId"])
        XCTAssertNil(object["userId"])
        XCTAssertEqual(headers["Authorization"], "Bearer \(Self.jwt.rawValue)")
        XCTAssertEqual(headers["Connect-Protocol-Version"], "1")
    }

    func testDecodesNumberAndStringInt64Totals() async throws {
        let client = DashboardClient { request in
            try Self.ok(
                request,
                #"""
                {
                  "totalInputTokens": 10,
                  "totalOutputTokens": "20",
                  "totalCacheWriteTokens": 30,
                  "totalCacheReadTokens": "40",
                  "aggregations": [
                    {
                      "modelIntent": "alpha",
                      "inputTokens": "5",
                      "outputTokens": 5,
                      "cacheReadTokens": "10",
                      "totalCents": 1.5
                    }
                  ]
                }
                """#
            )
        }
        let summary = try await client.getAggregatedUsageEvents(
            access: Self.jwt,
            startDateMs: 1,
            endDateMs: 2,
            seatID: .seat2
        )
        XCTAssertEqual(summary.seatID, .seat2)
        XCTAssertEqual(summary.totals.total, 100)
        XCTAssertEqual(summary.models.count, 1)
        XCTAssertEqual(summary.models[0].buckets.cacheWrite, 0)
        XCTAssertEqual(summary.models[0].buckets.total, 20)
    }

    func testOmittedCacheWriteBecomesZero() throws {
        let dto = GetAggregatedUsageEventsWireDTO(
            aggregations: [
                ModelUsageAggregationWireDTO(
                    modelIntent: "solo",
                    inputTokens: FlexibleInt64(value: 3),
                    outputTokens: FlexibleInt64(value: 1),
                    cacheWriteTokens: nil,
                    cacheReadTokens: FlexibleInt64(value: 2),
                    totalCents: nil,
                    requestCost: nil,
                    tier: nil
                ),
            ],
            totalInputTokens: FlexibleInt64(value: 3),
            totalOutputTokens: FlexibleInt64(value: 1),
            totalCacheWriteTokens: nil,
            totalCacheReadTokens: FlexibleInt64(value: 2),
            totalCostCents: nil,
            percentOfBurstUsed: nil,
            totalRequestCost: nil
        )
        let summary = try DashboardAggregatedUsageWire.summary(from: dto, seatID: .seat1)
        XCTAssertEqual(summary.totals.cacheWrite, 0)
        XCTAssertEqual(summary.totals.total, 6)
        XCTAssertEqual(summary.models[0].buckets.cacheWrite, 0)
    }

    func testNegativeTotalsRejected() async throws {
        let client = DashboardClient { request in
            try Self.ok(
                request,
                #"{"totalInputTokens":-1,"totalOutputTokens":0,"totalCacheWriteTokens":0,"totalCacheReadTokens":0}"#
            )
        }
        do {
            _ = try await client.getAggregatedUsageEvents(
                access: Self.jwt,
                startDateMs: 1,
                endDateMs: 2
            )
            XCTFail("expected decode failure")
        } catch let error as DashboardClient.ClientError {
            XCTAssertEqual(error, .decode)
        }
    }

    func testMalformedAggregationRejected() async throws {
        let client = DashboardClient { request in
            try Self.ok(
                request,
                #"{"totalInputTokens":1,"totalOutputTokens":0,"totalCacheWriteTokens":0,"totalCacheReadTokens":0,"aggregations":[{"inputTokens":1}]}"#
            )
        }
        do {
            _ = try await client.getAggregatedUsageEvents(
                access: Self.jwt,
                startDateMs: 1,
                endDateMs: 2
            )
            XCTFail("expected decode failure")
        } catch let error as DashboardClient.ClientError {
            XCTAssertEqual(error, .decode)
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
