import CursorBarAdapters
import CursorBarDomain
import XCTest

final class UsageSeriesAllTimeConcurrencyTests: XCTestCase {
    func testAllTimeChunkWorkIsBoundedNotSerialSeatTimesMonth() async throws {
        let seat1 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat1.sig"))
        let seat2 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat2.sig"))
        let inFlight = InFlightCounter()
        let delayNs: UInt64 = 40_000_000
        let client = DashboardClient { request in
            guard request.url?.lastPathComponent == "GetDailySpendByCategory" else {
                return try Self.ok(request, "{}")
            }
            await inFlight.enter()
            try await Task.sleep(nanoseconds: delayNs)
            await inFlight.leave()
            let start = UsageDayKey(year: 2025, month: 11, day: 1).utcMidnightMs
            return try Self.ok(request, Self.dailyJSON(dayMs: start, tokens: 1))
        }
        let refresher = UsageSeriesRefresher(client: client, maxConcurrentChunks: 5)
        let start = UsageDayKey(year: 2025, month: 11, day: 1)
        let end = UsageDayKey(year: 2026, month: 1, day: 15)
        let range = UsageRange.allTime(start: start, end: end)
        let began = ContinuousClock.now
        let commit = await refresher.refresh(
            credentials: [
                .init(seatID: .seat1, access: seat1),
                .init(seatID: .seat2, access: seat2),
            ],
            scope: .allAccounts,
            range: range,
            seatStarts: [
                .seat1: UsageDayKey(year: 2025, month: 12, day: 1),
                .seat2: start,
            ],
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let elapsed = ContinuousClock.now - began
        guard case .applied(let report) = commit else {
            return XCTFail("expected applied")
        }
        let maxInFlight = await inFlight.maxValue
        let observed = await refresher.maxObservedInFlight()
        XCTAssertLessThanOrEqual(maxInFlight, 5)
        XCTAssertLessThanOrEqual(observed, 5)
        XCTAssertGreaterThan(maxInFlight, 1, "expected parallel chunk work")
        // Serial lower bound for ~5–6 months across 2 seats would be many delays.
        // Parallel with cap 5 should finish in a small multiple of one delay.
        let serialFloor = Duration.nanoseconds(Int64(delayNs) * 8)
        XCTAssertLessThan(elapsed, serialFloor)
        XCTAssertGreaterThan(report.chunkCount, 0)
        XCTAssertEqual(
            report.series.rangeStart,
            start
        )
    }

    func testAllTimeDoesNotFetchEveryMonthSinceCreatedAt() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.series-budget.sig"))
        let tz = TimeZone(secondsFromGMT: 0)!
        let start = UsageDayKey(year: 2024, month: 1, day: 1)
        let end = UsageDayKey(year: 2026, month: 8, day: 15)
        let unbounded = UsageRangeChunks.months(from: start, through: end, timeZone: tz).count
        XCTAssertGreaterThan(unbounded, HistoryWarmBudget.default.maxMonths)
        nonisolated(unsafe) var calls = 0
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetDailySpendByCategory" {
                calls += 1
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageSeriesRefresher(client: client)
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

    func testScopeSwitchReusesHistoricalMonthCache() async throws {
        let seat1 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat1.sig"))
        let seat2 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat2.sig"))
        nonisolated(unsafe) var calls = 0
        let month = YearMonth(year: 2024, month: 8)
        let dayMs = month.overlappingUTCDays(timeZone: TimeZone(secondsFromGMT: 0)!).start.utcMidnightMs
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetDailySpendByCategory" {
                calls += 1
                return try Self.ok(request, Self.dailyJSON(dayMs: dayMs, tokens: 3))
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageSeriesRefresher(client: client)
        let range = UsageRange.month(month)
        let tz = TimeZone(secondsFromGMT: 0)!
        _ = await refresher.refresh(
            credentials: [
                .init(seatID: .seat1, access: seat1),
                .init(seatID: .seat2, access: seat2),
            ],
            scope: .allAccounts,
            range: range,
            timeZone: tz
        )
        let afterAll = calls
        _ = await refresher.refresh(
            credentials: [
                .init(seatID: .seat1, access: seat1),
                .init(seatID: .seat2, access: seat2),
            ],
            scope: .account(.seat2),
            range: range,
            timeZone: tz
        )
        XCTAssertEqual(calls, afterAll, "individual scope should reuse per-seat month cache")
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

    private static func dailyJSON(dayMs: Int64, tokens: Int64) -> String {
        #"{"dailySpend":[{"day":"\#(dayMs)","category":"default","totalTokens":"\#(tokens)"}]}"#
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
