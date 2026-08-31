import CursorBarAdapters
import CursorBarDomain
import XCTest

final class UsageInsightsMemoryReleaseTests: XCTestCase {
    func testReleaseRawEventsClearsCacheAndKeepsLastInsights() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.release.sig"))
        let client = DashboardClient { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
            return (Data(json.utf8), response)
        }
        let refresher = UsageInsightsRefresher(client: client)
        let commit = await refresher.refresh(
            credentials: [.init(seatID: .seat1, access: token)],
            scope: .account(.seat1),
            range: .defaultMonth(timeZone: TimeZone(secondsFromGMT: 0)!),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            includeMonthOverMonth: false
        )
        guard case .applied = commit else {
            return XCTFail("expected applied")
        }
        let cachedBefore = await refresher.eventCacheEntryCount()
        let insightsBefore = await refresher.lastKnownInsights()
        XCTAssertGreaterThan(cachedBefore, 0)
        XCTAssertNotNil(insightsBefore)
        await refresher.releaseRawEvents(keepingCurrentMonth: false)
        let cachedAfter = await refresher.eventCacheEntryCount()
        let insightsAfter = await refresher.lastKnownInsights()
        XCTAssertEqual(cachedAfter, 0)
        XCTAssertNotNil(insightsAfter)
    }

    func testReleaseRawEventsKeepingCurrentMonthDropsOlderMonthsOnly() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.release.current.sig"))
        let utc = TimeZone(secondsFromGMT: 0)!
        let current = YearMonth.current(timeZone: utc)
        let client = DashboardClient { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
            return (Data(json.utf8), response)
        }
        let refresher = UsageInsightsRefresher(client: client)
        let credential = UsageInsightsRefresher.SeatCredential(seatID: .seat1, access: token)
        _ = await refresher.refresh(
            credentials: [credential],
            scope: .account(.seat1),
            range: .month(current),
            timeZone: utc,
            includeMonthOverMonth: true
        )
        let cachedBefore = await refresher.eventCacheEntryCount()
        XCTAssertGreaterThanOrEqual(cachedBefore, 2)
        await refresher.releaseRawEvents(keepingCurrentMonth: true, timeZone: utc)
        let cachedAfter = await refresher.eventCacheEntryCount()
        XCTAssertEqual(cachedAfter, 1)
        await refresher.releaseRawEvents(keepingCurrentMonth: false)
        let cachedEmpty = await refresher.eventCacheEntryCount()
        let insightsAfter = await refresher.lastKnownInsights()
        XCTAssertEqual(cachedEmpty, 0)
        XCTAssertNotNil(insightsAfter)
    }
}
