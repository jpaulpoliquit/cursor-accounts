import CursorBarAdapters
import CursorBarDomain
import XCTest

final class UsageTokenSummaryAllTimeChunkTests: XCTestCase {
    func testOldWindowFailureStillReturnsLaterChunks() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let tz = TimeZone(secondsFromGMT: 0)!
        let firstMonthStart = YearMonth(year: 2024, month: 11).utcHalfOpenIntervalMs(timeZone: tz).startMs
        let client = DashboardClient { request in
            guard request.url?.lastPathComponent == "GetAggregatedUsageEvents" else {
                return try Self.ok(request, "{}")
            }
            let object = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
            let startDate = (object?["startDate"] as? NSNumber)?.int64Value
            if startDate == firstMonthStart {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
            return try Self.ok(request, Self.aggregateJSON(input: 25, models: [("solo", 25)]))
        }
        let refresher = UsageTokenSummaryRefresher(client: client)
        let start = UsageDayKey(year: 2024, month: 11, day: 1)
        let end = UsageDayKey(year: 2025, month: 1, day: 15)
        let commit = await refresher.refresh(
            credentials: [.init(seatID: .seat1, access: token)],
            scope: .account(.seat1),
            range: .allTime(start: start, end: end),
            seatStarts: [.seat1: start],
            timeZone: tz
        )
        guard case .applied(let report) = commit else {
            return XCTFail("expected applied")
        }
        XCTAssertGreaterThan(report.summary.totals.total, 0)
        XCTAssertNotNil(report.summary.temporalCoverage)
        XCTAssertFalse(report.summary.temporalCoverage?.isComplete ?? true)
        XCTAssertNotNil(report.summary.temporalCoverage?.caption)
    }

    func testAllTimeDoesNotFetchEveryMonthSinceCreatedAt() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.token-budget.sig"))
        let tz = TimeZone(secondsFromGMT: 0)!
        let start = UsageDayKey(year: 2024, month: 1, day: 1)
        let end = UsageDayKey(year: 2026, month: 8, day: 15)
        let unbounded = UsageRangeChunks.months(from: start, through: end, timeZone: tz).count
        XCTAssertGreaterThan(unbounded, HistoryWarmBudget.default.maxMonths)
        nonisolated(unsafe) var calls = 0
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetAggregatedUsageEvents" {
                calls += 1
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageTokenSummaryRefresher(client: client)
        let commit = await refresher.refresh(
            credentials: [.init(seatID: .seat1, access: token)],
            scope: .account(.seat1),
            range: .allTime(start: start, end: end),
            seatStarts: [.seat1: start],
            timeZone: tz
        )
        guard case .applied = commit else {
            return XCTFail("expected applied")
        }
        XCTAssertLessThanOrEqual(calls, HistoryWarmBudget.default.maxMonths)
        XCTAssertLessThan(calls, unbounded)
    }

    func testChunkMergeIsDeterministicSum() {
        let a = SeatUsageTokenSummary(
            seatID: .seat1,
            totals: TokenBucketCounts(input: 10, output: 0, cacheWrite: 0, cacheRead: 0)!,
            models: [
                ModelUsageRow(
                    modelIntent: "a",
                    displayName: "A",
                    buckets: TokenBucketCounts(input: 10, output: 0, cacheWrite: 0, cacheRead: 0)!
                ),
            ]
        )
        let b = SeatUsageTokenSummary(
            seatID: .seat1,
            totals: TokenBucketCounts(input: 5, output: 7, cacheWrite: 0, cacheRead: 0)!,
            models: [
                ModelUsageRow(
                    modelIntent: "a",
                    displayName: "A",
                    buckets: TokenBucketCounts(input: 5, output: 0, cacheWrite: 0, cacheRead: 0)!
                ),
                ModelUsageRow(
                    modelIntent: "b",
                    displayName: "B",
                    buckets: TokenBucketCounts(input: 0, output: 7, cacheWrite: 0, cacheRead: 0)!
                ),
            ]
        )
        let merged = UsageTokenSummaryAggregator.mergeSeatChunks([a, b])
        XCTAssertEqual(merged?.totals.total, 22)
        XCTAssertEqual(merged?.models.first(where: { $0.modelIntent == "a" })?.buckets.total, 15)
        XCTAssertEqual(merged?.models.first(where: { $0.modelIntent == "b" })?.buckets.total, 7)
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

    private static func aggregateJSON(input: Int64, models: [(String, Int64)]) -> String {
        let modelJSON = models.map { intent, tokens in
            #"{"modelIntent":"\#(intent)","inputTokens":"\#(tokens)","outputTokens":"0","cacheWriteTokens":"0","cacheReadTokens":"0"}"#
        }.joined(separator: ",")
        return #"{"totalInputTokens":"\#(input)","totalOutputTokens":"0","totalCacheWriteTokens":"0","totalCacheReadTokens":"0","aggregations":[\#(modelJSON)]}"#
    }
}
