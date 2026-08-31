import CursorBarAdapters
import CursorBarDomain
import XCTest

final class UsageInsightsAllTimeBudgetTests: XCTestCase {
    func testAllTimeDoesNotPageEveryMonthSinceCreatedAt() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.budget.sig"))
        let tz = TimeZone(secondsFromGMT: 0)!
        let start = UsageDayKey(year: 2025, month: 1, day: 31)
        let end = UsageDayKey(year: 2026, month: 8, day: 15)
        let unbounded = UsageRangeChunks.months(from: start, through: end, timeZone: tz).count
        XCTAssertGreaterThan(unbounded, HistoryWarmBudget.interactiveAllTime.maxMonths)

        nonisolated(unsafe) var calls = 0
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetFilteredUsageEvents" {
                calls += 1
            }
            return try Self.emptyOK(request)
        }
        let refresher = UsageInsightsRefresher(client: client)
        let commit = await refresher.refresh(
            credentials: [.init(seatID: .seat1, access: token)],
            scope: .account(.seat1),
            range: .allTime(start: start, end: end),
            timeZone: tz,
            includeMonthOverMonth: false,
            seatStarts: [.seat1: start]
        )
        guard case .applied = commit else {
            return XCTFail("expected applied")
        }
        XCTAssertLessThanOrEqual(calls, HistoryWarmBudget.interactiveAllTime.maxMonths)
        XCTAssertLessThan(calls, unbounded)
    }

    func testAllTimeStopsAfterEventBudgetOnRecentMonths() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.events.sig"))
        let tz = TimeZone(secondsFromGMT: 0)!
        let start = UsageDayKey(year: 2026, month: 3, day: 1)
        let end = UsageDayKey(year: 2026, month: 8, day: 15)
        nonisolated(unsafe) var calls = 0
        let client = DashboardClient { request in
            calls += 1
            return try Self.oneEventOK(request, stampMs: end.utcMidnightMs)
        }
        let refresher = UsageInsightsRefresher(client: client)
        let budget = HistoryWarmBudget(maxMonths: 12, maxEvents: 2)
        let commit = await refresher.refresh(
            credentials: [.init(seatID: .seat1, access: token)],
            scope: .account(.seat1),
            range: .allTime(start: start, end: end),
            timeZone: tz,
            includeMonthOverMonth: false,
            seatStarts: [.seat1: start],
            allTimeBudget: budget
        )
        guard case .applied(let report) = commit else {
            return XCTFail("expected applied")
        }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(report.insights.totalRequests, 2)
        XCTAssertTrue(report.insights.coverage.truncated)
    }

    func testAllTimeEventFetchesAreConcurrencyGated() async throws {
        let tz = TimeZone(secondsFromGMT: 0)!
        let range = UsageRange.month(YearMonth(year: 2026, month: 8))
        let inFlight = InFlightCounter()
        let client = DashboardClient { request in
            guard request.url?.lastPathComponent == "GetFilteredUsageEvents" else {
                return try Self.emptyOK(request)
            }
            await inFlight.enter()
            try await Task.sleep(nanoseconds: 30_000_000)
            await inFlight.leave()
            return try Self.emptyOK(request)
        }
        let refresher = UsageInsightsRefresher(client: client, maxConcurrentFetches: 3)
        var credentials: [SeatUsageRefresher.SeatCredential] = []
        for index in 1...6 {
            let token = try XCTUnwrap(
                ConnectReadyAccessToken(validatedJWT: "header.gate\(index).sig")
            )
            let seatID = try XCTUnwrap(SeatID(rawValue: "seat\(index)"))
            credentials.append(.init(seatID: seatID, access: token))
        }
        _ = await refresher.refresh(
            credentials: credentials,
            scope: .allAccounts,
            range: range,
            timeZone: tz,
            includeMonthOverMonth: false
        )
        let maxInFlight = await inFlight.maxValue
        let observed = await refresher.maxObservedInFlight()
        XCTAssertLessThanOrEqual(maxInFlight, 3)
        XCTAssertLessThanOrEqual(observed, 3)
        XCTAssertGreaterThan(maxInFlight, 1)
    }

    private static func emptyOK(_ request: URLRequest) throws -> (Data, URLResponse) {
        try ok(request, #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#)
    }

    private static func oneEventOK(_ request: URLRequest, stampMs: Int64) throws -> (Data, URLResponse) {
        try ok(
            request,
            """
            {
              "totalUsageEventsCount": 1,
              "usageEventsDisplay": [
                {"timestamp":"\(stampMs)","model":"m","kind":"USAGE_EVENT_KIND_USAGE_BASED",
                 "tokenUsage":{"inputTokens":1,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0}}
              ],
              "usageEvents": []
            }
            """
        )
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

private actor InFlightCounter {
    private var current = 0
    private(set) var maxValue = 0

    func enter() {
        current += 1
        maxValue = max(maxValue, current)
    }

    func leave() {
        current -= 1
    }
}
