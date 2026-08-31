@testable import CursorBar
import CursorBarAdapters
import CursorBarDomain
import XCTest

@MainActor
final class UsageRefreshGenerationTests: XCTestCase {
    func testCoordinatorKeepsRefreshingPhaseUntilAppliedCommit() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            return try usageGenFixtureOK(
                request,
                usageGenFixtureJSON(method: method, totalPercent: 33)
            )
        }
        let refresher = SeatUsageRefresher(client: client)
        var applied = 0
        let coordinator = UsageRefreshCoordinator(refresher: refresher)
        coordinator.configure(
            loadCredentials: {
                [SeatUsageRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            applyReport: { _ in applied += 1 },
            onChange: {}
        )

        coordinator.refresh(seatID: .seat1)
        for _ in 0..<150 {
            if case .settled = coordinator.phase { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        guard case .settled(let report) = coordinator.phase,
              case .refreshed(let snap)? = report.outcomes[.seat1]
        else {
            return XCTFail("expected settled applied refresh, phase=\(coordinator.phase)")
        }
        XCTAssertEqual(snap.period.usage.totalPercentUsed.percent, 33, accuracy: 0.001)
        XCTAssertEqual(applied, 1)
    }
}

private func usageGenFixtureOK(_ request: URLRequest, _ json: String) throws -> (Data, URLResponse) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (Data(json.utf8), response)
}

private func usageGenFixtureJSON(method: String, totalPercent: Double) -> String {
    switch method {
    case "GetPlanInfo":
        return #"{"planInfo":{"planName":"ultra","includedAmountCents":20000,"price":"$200"}}"#
    case "GetCurrentPeriodUsage":
        return """
        {"planUsage":{"autoPercentUsed":1,"apiPercentUsed":2,"totalPercentUsed":\(totalPercent)},"spendLimitUsage":{"individualUsed":"0"}}
        """
    case "GetHardLimit":
        return #"{"noUsageBasedAllowed":true,"hardLimit":0}"#
    case "GetCreditGrantsBalance":
        return "{}"
    case "GetUsageLimitPolicyStatus":
        return #"{"canAdjustOnDemand":true,"canConfigureSpendLimit":true}"#
    default:
        return "{}"
    }
}
