import CursorBarAdapters
import CursorBarDomain
import XCTest

final class UsageTokenSummaryRefresherTests: XCTestCase {
    func testTwoSeatSumAndPartialCoverage() async throws {
        let seat1 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat1.sig"))
        let seat2 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat2.sig"))
        let client = DashboardClient { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if request.url?.lastPathComponent == "GetAggregatedUsageEvents" {
                if auth.contains("seat1") {
                    return try Self.ok(request, Self.aggregateJSON(input: 10, models: [("alpha", 10)]))
                }
                if auth.contains("seat2") {
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 500,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return (Data(), response)
                }
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageTokenSummaryRefresher(client: client)
        let range = UsageRange.month(YearMonth(year: 2024, month: 8))
        let commit = await refresher.refresh(
            credentials: [
                .init(seatID: .seat1, access: seat1),
                .init(seatID: .seat2, access: seat2),
            ],
            scope: .allAccounts,
            range: range,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        guard case .applied(let report) = commit else {
            return XCTFail("expected applied")
        }
        XCTAssertEqual(report.summary.totals.total, 10)
        XCTAssertEqual(report.summary.coverage.caption, "1 of 2 accounts")
        let share = try XCTUnwrap(report.summary.topModels.first?.share)
        XCTAssertEqual(share, 1.0, accuracy: 0.0001)
    }

    func testHistoricalMonthUsesImmutableCache() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        nonisolated(unsafe) var calls = 0
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetAggregatedUsageEvents" {
                calls += 1
                return try Self.ok(request, Self.aggregateJSON(input: 44, models: [("solo", 44)]))
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageTokenSummaryRefresher(client: client)
        let range = UsageRange.month(YearMonth(year: 2024, month: 1))
        let tz = TimeZone(secondsFromGMT: 0)!
        _ = await refresher.refresh(
            credentials: [.init(seatID: .seat1, access: token)],
            scope: .account(.seat1),
            range: range,
            timeZone: tz,
            now: Date(timeIntervalSince1970: 1_750_000_000)
        )
        _ = await refresher.refresh(
            credentials: [.init(seatID: .seat1, access: token)],
            scope: .account(.seat1),
            range: range,
            timeZone: tz,
            now: Date(timeIntervalSince1970: 1_750_000_000)
        )
        XCTAssertEqual(calls, 1)
    }

    func testReleaseHistoricalMonthsDropsCacheAndKeepsLastKnown() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.release-months.sig"))
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetAggregatedUsageEvents" {
                return try Self.ok(request, Self.aggregateJSON(input: 44, models: [("solo", 44)]))
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageTokenSummaryRefresher(client: client)
        let range = UsageRange.month(YearMonth(year: 2024, month: 1))
        let tz = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        _ = await refresher.refresh(
            credentials: [.init(seatID: .seat1, access: token)],
            scope: .account(.seat1),
            range: range,
            timeZone: tz,
            now: now
        )
        let cachedBefore = await refresher.monthCacheEntryCount()
        let summaryBefore = await refresher.lastKnownSummary()
        XCTAssertEqual(cachedBefore, 1)
        XCTAssertEqual(summaryBefore?.totals.total, 44)
        await refresher.releaseHistoricalMonths(keepingCurrentMonth: false)
        let cachedAfter = await refresher.monthCacheEntryCount()
        let summaryAfter = await refresher.lastKnownSummary()
        XCTAssertEqual(cachedAfter, 0)
        XCTAssertEqual(summaryAfter?.totals.total, 44)
    }

    func testStaleGenerationDiscardedAndLastKnownRetainedOnFailure() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let gate = AggregateStallGate()
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetAggregatedUsageEvents" {
                await gate.waitIfFirst()
                let input = await gate.tokensForCurrentRequest()
                return try Self.ok(request, Self.aggregateJSON(input: input, models: [("solo", input)]))
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageTokenSummaryRefresher(client: client)
        let range = UsageRange.month(YearMonth(year: 2024, month: 8))
        let credential = UsageTokenSummaryRefresher.SeatCredential(seatID: .seat1, access: token)

        await gate.armFirstHold()
        async let slow = refresher.refresh(
            credentials: [credential],
            scope: .account(.seat1),
            range: range,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        await gate.waitUntilFirstHeld()
        await gate.setFastTokens(321)
        let fast = await refresher.refresh(
            credentials: [credential],
            scope: .account(.seat1),
            range: range,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        guard case .applied(let fastReport) = fast else {
            return XCTFail("expected fast applied")
        }
        XCTAssertEqual(fastReport.summary.totals.total, 321)
        await gate.releaseFirst()
        let slowCommit = await slow
        XCTAssertEqual(slowCommit, .discarded)
        let lastKnown = await refresher.lastKnownSummary()
        XCTAssertEqual(lastKnown?.totals.total, 321)

        nonisolated(unsafe) var fail = true
        let failing = UsageTokenSummaryRefresher(client: DashboardClient { request in
            if fail, request.url?.lastPathComponent == "GetAggregatedUsageEvents" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
            return try Self.ok(request, Self.aggregateJSON(input: 9, models: [("solo", 9)]))
        })
        fail = false
        _ = await failing.refresh(
            credentials: [credential],
            scope: .account(.seat1),
            range: range,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        fail = true
        let kept = await failing.refresh(
            credentials: [credential],
            scope: .account(.seat1),
            range: range,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        guard case .applied(let report) = kept else {
            return XCTFail("expected retained")
        }
        XCTAssertEqual(report.summary.totals.total, 9)
    }

    func testDropSeatCachesPreventsSameSeatIDResurrection() async throws {
        let tokenA = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.summaryA.sig"))
        let tokenB = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.summaryB.sig"))
        let month = YearMonth.current().previous
        let range = UsageRange.month(month)
        nonisolated(unsafe) var calls = 0
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetAggregatedUsageEvents" {
                calls += 1
                let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
                let input: Int64 = auth.contains("summaryA") ? 111 : 222
                return try Self.ok(request, Self.aggregateJSON(input: input, models: [("solo", input)]))
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageTokenSummaryRefresher(client: client)
        let credA = UsageTokenSummaryRefresher.SeatCredential(seatID: .seat1, access: tokenA)
        let credB = UsageTokenSummaryRefresher.SeatCredential(seatID: .seat1, access: tokenB)
        let tz = TimeZone(secondsFromGMT: 0)!
        let appliedA = await refresher.refresh(
            credentials: [credA],
            scope: .account(.seat1),
            range: range,
            timeZone: tz
        )
        guard case .applied(let reportA) = appliedA else { return XCTFail("seed A") }
        XCTAssertEqual(reportA.summary.totals.total, 111)
        XCTAssertEqual(calls, 1)
        await refresher.dropSeatCaches(seatID: .seat1)
        calls = 0
        let appliedB = await refresher.refresh(
            credentials: [credB],
            scope: .account(.seat1),
            range: range,
            timeZone: tz
        )
        guard case .applied(let reportB) = appliedB else { return XCTFail("apply B") }
        XCTAssertEqual(calls, 1, "B must not hit A's historical month cache")
        XCTAssertEqual(reportB.summary.totals.total, 222)
    }

    private static func aggregateJSON(input: Int64, models: [(String, Int64)]) -> String {
        let rows = models.map { intent, tokens in
            #"{"modelIntent":"\#(intent)","inputTokens":"\#(tokens)","outputTokens":0,"cacheReadTokens":0}"#
        }.joined(separator: ",")
        return #"{"totalInputTokens":"\#(input)","totalOutputTokens":0,"totalCacheWriteTokens":0,"totalCacheReadTokens":0,"aggregations":[\#(rows)]}"#
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

private actor AggregateStallGate {
    private var holdFirst = false
    private var firstHeld = false
    private var tokens: Int64 = 1
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func armFirstHold() {
        holdFirst = true
        firstHeld = false
        tokens = 1
    }

    func waitIfFirst() async {
        guard holdFirst, !firstHeld else { return }
        firstHeld = true
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilFirstHeld() async {
        while !firstHeld {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func releaseFirst() {
        holdFirst = false
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    func setFastTokens(_ value: Int64) {
        tokens = value
    }

    func tokensForCurrentRequest() -> Int64 {
        tokens
    }
}
