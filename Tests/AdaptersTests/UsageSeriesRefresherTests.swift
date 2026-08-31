@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class UsageSeriesRefresherTests: XCTestCase {
    func testOlderCompletionCannotOverwriteNewerSeries() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let gate = SeriesStallGate()
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                await gate.waitIfFirst()
                let tokens = await gate.tokensForCurrentRequest()
                return try Self.ok(request, Self.dailyJSON(dayMs: 1_722_470_400_000, tokens: tokens))
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageSeriesRefresher(client: client)
        let credential = UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)
        // Historical month so overlapping UTC day matches fixture midnight.
        let range = UsageRange.month(YearMonth(year: 2024, month: 8))

        await gate.armFirstHold()
        let slow = Task {
            await refresher.refresh(credentials: [credential], scope: .account(.seat1), range: range)
        }
        await gate.waitUntilFirstHeld()

        await gate.setFastTokens(999)
        let fast = await refresher.refresh(credentials: [credential], scope: .account(.seat1), range: range)
        guard case .applied(let fastReport) = fast else {
            return XCTFail("expected fast apply")
        }
        XCTAssertEqual(fastReport.series.points.first(where: { $0.tokens == 999 })?.tokens, 999)

        await gate.releaseFirst()
        let slowCommit = await slow.value
        XCTAssertEqual(slowCommit, .discarded)
        let retained = await refresher.lastKnownSeries()
        XCTAssertEqual(retained?.points.first(where: { $0.tokens == 999 })?.tokens, 999)
    }

    func testFailedRefreshKeepsLastKnownSeries() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let credential = UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)
        let range = UsageRange.month(YearMonth(year: 2024, month: 8))
        nonisolated(unsafe) var calls = 0
        let sequenced = DashboardClient { request in
            calls += 1
            let method = request.url?.lastPathComponent ?? ""
            if calls == 1, method == "GetDailySpendByCategory" {
                return try Self.ok(request, Self.dailyJSON(dayMs: 1_722_470_400_000, tokens: 77))
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        let keeper = UsageSeriesRefresher(client: sequenced)
        let ok = await keeper.refresh(credentials: [credential], scope: .account(.seat1), range: range)
        guard case .applied = ok else { return XCTFail("seed apply") }
        let afterFail = await keeper.refresh(credentials: [credential], scope: .account(.seat1), range: range)
        guard case .applied(let kept) = afterFail else {
            return XCTFail("expected applied keep")
        }
        XCTAssertEqual(kept.series.points.first(where: { $0.tokens == 77 })?.tokens, 77)
        let last = await keeper.lastKnownSeries()
        XCTAssertEqual(last?.points.first(where: { $0.tokens == 77 })?.tokens, 77)
    }

    func testCacheHitAvoidsDuplicateFetchForHistoricalMonth() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let credential = UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)
        let month = YearMonth.current().previous
        let range = UsageRange.month(month)
        let dayMs = month.overlappingUTCDays(timeZone: .current).start.utcMidnightMs
        nonisolated(unsafe) var dailyCalls = 0
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetDailySpendByCategory" {
                dailyCalls += 1
                return try Self.ok(request, Self.dailyJSON(dayMs: dayMs, tokens: 11))
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageSeriesRefresher(client: client)
        _ = await refresher.refresh(credentials: [credential], scope: .account(.seat1), range: range)
        _ = await refresher.refresh(credentials: [credential], scope: .account(.seat1), range: range)
        XCTAssertEqual(dailyCalls, 1)
        let fetches = await refresher.networkFetchCount(seatID: .seat1, month: month)
        XCTAssertEqual(fetches, 1)
    }

    func testDropSeatCachesPreventsSeatIDBleedAndLastKnownResurrection() async throws {
        let tokenA = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.accountA.sig"))
        let tokenB = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.accountB.sig"))
        let month = YearMonth.current().previous
        let range = UsageRange.month(month)
        let dayMs = month.overlappingUTCDays(timeZone: .current).start.utcMidnightMs
        nonisolated(unsafe) var dailyCalls = 0
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetDailySpendByCategory" {
                dailyCalls += 1
                let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
                let tokens: Int64 = auth.contains("accountA") ? 111 : 222
                return try Self.ok(request, Self.dailyJSON(dayMs: dayMs, tokens: tokens))
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageSeriesRefresher(client: client)
        let credA = UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: tokenA)
        let credB = UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: tokenB)

        let appliedA = await refresher.refresh(
            credentials: [credA],
            scope: .allAccounts,
            range: range
        )
        guard case .applied(let reportA) = appliedA else {
            return XCTFail("seed A")
        }
        XCTAssertEqual(reportA.series.points.first(where: { $0.tokens == 111 })?.tokens, 111)
        let knownAfterA = await refresher.lastKnownSeries()
        XCTAssertEqual(knownAfterA?.points.first(where: { $0.tokens == 111 })?.tokens, 111)
        XCTAssertEqual(dailyCalls, 1)

        await refresher.dropSeatCaches(seatID: .seat1)
        let knownAfterDrop = await refresher.lastKnownSeries()
        XCTAssertNil(knownAfterDrop)

        // Failure after drop must not resurrect A's last-known.
        nonisolated(unsafe) var failOnce = true
        let failingClient = DashboardClient { request in
            if failOnce, request.url?.lastPathComponent == "GetDailySpendByCategory" {
                failOnce = false
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
            return try Self.ok(request, Self.dailyJSON(dayMs: dayMs, tokens: 222))
        }
        let failing = UsageSeriesRefresher(client: failingClient)
        _ = await failing.refresh(credentials: [credA], scope: .allAccounts, range: range)
        await failing.dropSeatCaches(seatID: .seat1)
        let failed = await failing.refresh(credentials: [credB], scope: .allAccounts, range: range)
        guard case .applied(let failedReport) = failed else {
            return XCTFail("expected apply after drop")
        }
        XCTAssertFalse(failedReport.series.points.contains(where: { $0.tokens == 111 }))
        let knownAfterFail = await failing.lastKnownSeries()
        XCTAssertNil(knownAfterFail?.points.first(where: { $0.tokens == 111 }))

        // B on same SeatID must miss A's historical cache and refetch.
        dailyCalls = 0
        let appliedB = await refresher.refresh(
            credentials: [credB],
            scope: .account(.seat1),
            range: range
        )
        guard case .applied(let reportB) = appliedB else {
            return XCTFail("B apply")
        }
        XCTAssertEqual(dailyCalls, 1, "B must not hit A's historical month cache")
        XCTAssertEqual(reportB.series.points.first(where: { $0.tokens == 222 })?.tokens, 222)
    }

    func testPerAccountFailureDoesNotEraseOtherPoints() async throws {
        let seat1 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat1.sig"))
        let seat2 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat2.sig"))
        let today = UsageDayKey.utcDay(containing: Date())
        let dayMs = today.utcMidnightMs
        let range = UsageRange.defaultMonth()
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if auth.contains("seat2") {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
            if method == "GetDailySpendByCategory" {
                return try Self.ok(request, Self.dailyJSON(dayMs: dayMs, tokens: 55))
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageSeriesRefresher(client: client)
        let commit = await refresher.refresh(
            credentials: [
                .init(seatID: .seat1, access: seat1),
                .init(seatID: .seat2, access: seat2),
            ],
            scope: .allAccounts,
            range: range
        )
        guard case .applied(let report) = commit else {
            return XCTFail("expected applied")
        }
        guard case .refreshed(let okSeries)? = report.outcomes[.seat1] else {
            return XCTFail("seat1 should refresh")
        }
        guard case .failed? = report.outcomes[.seat2] else {
            return XCTFail("seat2 should fail")
        }
        XCTAssertEqual(okSeries.points.first(where: { $0.day == today })?.tokens, 55)
        XCTAssertEqual(report.series.points.first(where: { $0.day == today })?.tokens, 55)
        XCTAssertTrue(report.series.coverage.isPartial)
        XCTAssertEqual(report.series.coverage.caption, "1 of 2 accounts")
        XCTAssertEqual(report.series.points.first(where: { $0.day == today })?.coverage, .partial)
    }

    func testReleaseHistoricalChunksDropsCacheAndKeepsLastKnown() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.release-chunks.sig"))
        let credential = UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)
        let month = YearMonth.current().previous
        let range = UsageRange.month(month)
        let dayMs = month.overlappingUTCDays(timeZone: .current).start.utcMidnightMs
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetDailySpendByCategory" {
                return try Self.ok(request, Self.dailyJSON(dayMs: dayMs, tokens: 11))
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageSeriesRefresher(client: client)
        _ = await refresher.refresh(credentials: [credential], scope: .account(.seat1), range: range)
        let cachedBefore = await refresher.chunkCacheEntryCount()
        let knownBefore = await refresher.lastKnownSeries()
        XCTAssertEqual(cachedBefore, 1)
        XCTAssertNotNil(knownBefore)
        await refresher.releaseHistoricalChunks(keepingCurrentMonth: false)
        let cachedAfter = await refresher.chunkCacheEntryCount()
        let knownAfter = await refresher.lastKnownSeries()
        XCTAssertEqual(cachedAfter, 0)
        XCTAssertEqual(knownAfter?.points.first(where: { $0.tokens == 11 })?.tokens, 11)
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

private actor SeriesStallGate {
    private var holdFirst = false
    private var firstHeld = false
    private var firstReleased = false
    private var tokens: Int64 = 1

    func armFirstHold() {
        holdFirst = true
        firstHeld = false
        firstReleased = false
        tokens = 1
    }

    func waitIfFirst() async {
        guard holdFirst else { return }
        if !firstHeld {
            firstHeld = true
            while !firstReleased {
                await Task.yield()
            }
            holdFirst = false
        }
    }

    func waitUntilFirstHeld() async {
        while !firstHeld {
            await Task.yield()
        }
    }

    func releaseFirst() {
        firstReleased = true
    }

    func setFastTokens(_ value: Int64) {
        tokens = value
    }

    func tokensForCurrentRequest() -> Int64 {
        tokens
    }
}
