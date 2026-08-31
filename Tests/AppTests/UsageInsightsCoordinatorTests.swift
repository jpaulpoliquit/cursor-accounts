import CursorBarAdapters
import CursorBarDomain
import XCTest

@testable import CursorBar

@MainActor
final class UsageInsightsCoordinatorTests: XCTestCase {
    func testInsightsShareScopeAndRangeWithSeriesCoordinator() async throws {
        let client = DashboardClient { request in
            let path = request.url?.lastPathComponent ?? ""
            if path == "GetFilteredUsageEvents" {
                return try Self.okJSON(
                    request,
                    #"""
                    {
                      "totalUsageEventsCount": 2,
                      "usageEventsDisplay": [
                        {"timestamp":"1722470400000","model":"m","kind":"USAGE_EVENT_KIND_USAGE_BASED",
                         "tokenUsage":{"inputTokens":1,"outputTokens":1,"cacheReadTokens":0,"cacheWriteTokens":0}},
                        {"timestamp":"1722474000000","model":"m","kind":"USAGE_EVENT_KIND_USAGE_BASED",
                         "tokenUsage":{"inputTokens":1,"outputTokens":1,"cacheReadTokens":0,"cacheWriteTokens":0}}
                      ],
                      "usageEvents": []
                    }
                    """#
                )
            }
            if path == "GetAggregatedUsageEvents" {
                return try Self.okJSON(
                    request,
                    #"""
                    {
                      "totalInputTokens":"2","totalOutputTokens":"2",
                      "totalCacheWriteTokens":"0","totalCacheReadTokens":"0",
                      "aggregations":[]
                    }
                    """#
                )
            }
            if path == "GetDailySpendByCategory" {
                return try Self.okJSON(request, #"{"dailySpend":[]}"#)
            }
            return try Self.okJSON(request, "{}")
        }

        let tz = TimeZone(identifier: "Asia/Taipei")!
        let targetRange = UsageRange.month(YearMonth(year: 2024, month: 8))
        let coordinator = UsageSeriesCoordinator(
            refresher: UsageSeriesRefresher(client: client),
            tokenSummaryRefresher: UsageTokenSummaryRefresher(client: client),
            insightsRefresher: UsageInsightsRefresher(client: client),
            timeZone: tz
        )
        let access = ConnectReadyAccessToken(validatedJWT: "header.payload.signature")!
        coordinator.configure(
            loadCredentials: { [SeatUsageRefresher.SeatCredential(seatID: .seat1, access: access)] },
            connectedScopes: {
                [
                    (.allAccounts, "All Accounts"),
                    (.account(.seat1), "Seat 1"),
                ]
            },
            onChange: {}
        )
        coordinator.selectRange(targetRange)
        await wait(coordinator) {
            $0.phase == .settled && $0.insights?.range == targetRange
        }
        coordinator.selectScope(.account(.seat1))
        await wait(coordinator) {
            $0.phase == .settled
                && $0.scope == .account(.seat1)
                && $0.insights?.scope == .account(.seat1)
                && $0.insights?.range == targetRange
        }

        XCTAssertEqual(coordinator.scope, .account(.seat1))
        XCTAssertEqual(coordinator.range, targetRange)
        let insights = try XCTUnwrap(coordinator.insights)
        XCTAssertEqual(insights.scope, .account(.seat1))
        XCTAssertEqual(insights.range, targetRange)
        XCTAssertEqual(insights.totalRequests, 2)
        let accessibility = coordinator.insightsAccessibilityDescriptor.lowercased()
        XCTAssertFalse(accessibility.contains("agent hours"))
        XCTAssertTrue(accessibility.contains("estimated agent-active"))
    }

    private func wait(
        _ coordinator: UsageSeriesCoordinator,
        timeoutMs: Int = 4000,
        predicate: (UsageSeriesCoordinator) -> Bool
    ) async {
        let steps = max(timeoutMs / 20, 1)
        for _ in 0..<steps {
            if predicate(coordinator) { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    nonisolated private static func okJSON(_ request: URLRequest, _ json: String) throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(json.utf8), response)
    }
}
