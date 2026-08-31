@testable import CursorBar
import CursorBarAdapters
import CursorBarDomain
import XCTest

@MainActor
final class SeatBindingLifecycleTests: XCTestCase {
    func testDelayedCardRefreshDiscardedAfterBindingEpochAdvance() async throws {
        let tokenA = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.accountA.sig"))
        let tokenB = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.accountB.sig"))
        let registry = SeatBindingEpochRegistry()
        let gate = CardRefreshStallGate()

        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetCurrentPeriodUsage" {
                await gate.waitIfHeld()
            }
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            let percent = auth.contains("accountB") ? 77.0 : 11.0
            return try cardFixtureOK(request, cardFixtureJSON(method: method, totalPercent: percent))
        }
        let refresher = SeatUsageRefresher(client: client)
        var usageBySeat: [SeatID: SeatUsageSnapshot] = [:]

        let coordinator = UsageRefreshCoordinator(refresher: refresher)
        coordinator.configure(
            loadCredentials: {
                if gate.servingB {
                    return [.init(seatID: .seat1, access: tokenB)]
                }
                return [.init(seatID: .seat1, access: tokenA)]
            },
            applyReport: { report in
                for (seatID, outcome) in report.outcomes {
                    let captured = report.bindingEpochs[seatID] ?? 0
                    guard registry.isCurrent(seatID: seatID, epoch: captured) else { continue }
                    if case .refreshed(let snap) = outcome {
                        usageBySeat[seatID] = snap
                    }
                }
            },
            onChange: {},
            bindingEpoch: { seatID in registry.current(for: seatID) }
        )

        await gate.armHold()
        coordinator.refresh(seatID: .seat1)
        await gate.waitUntilHeld()

        _ = registry.advance(for: .seat1)
        await refresher.invalidateBinding(seatID: .seat1, epoch: registry.current(for: .seat1))
        gate.servingB = true

        await gate.releaseHold()
        for _ in 0..<100 {
            if case .settled = coordinator.phase { break }
            await Task.yield()
        }

        XCTAssertNil(usageBySeat[.seat1])

        coordinator.refresh(seatID: .seat1)
        for _ in 0..<150 {
            if let snap = usageBySeat[.seat1] { 
                XCTAssertEqual(snap.period.usage.totalPercentUsed.percent, 77, accuracy: 0.001)
                return
            }
            await Task.yield()
        }
        XCTFail("expected B snapshot after epoch-valid refresh")
    }

    func testAllTimeBoundLookupDiscardedWhenEpochAdvancesBeforeCommit() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.bound.sig"))
        let registry = SeatBindingEpochRegistry()
        let gate = CardRefreshStallGate()
        let captured = registry.snapshot(for: [.seat1])

        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetMe" {
                await gate.waitIfHeld()
            }
            return try cardFixtureOK(request, #"{"createdAt":"2024-01-01T00:00:00Z"}"#)
        }

        await gate.armHold()
        let lookup = Task {
            let resolved = await AllTimeBoundLookup.resolve(
                credentials: [.init(seatID: .seat1, access: token)],
                bindingEpochs: captured,
                client: client
            )
            guard captured.allSatisfy({ registry.isCurrent(seatID: $0.key, epoch: $0.value) }) else {
                return nil as AllTimeHistoryBounds?
            }
            return resolved
        }
        await gate.waitUntilHeld()
        _ = registry.advance(for: .seat1)
        await gate.releaseHold()

        let bounds = await lookup.value
        XCTAssertNil(bounds)
    }

    func testOtherSeatsUnaffectedBySeat1BindingAdvance() async throws {
        let token1 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat1.sig"))
        let token2 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat2.sig"))
        let registry = SeatBindingEpochRegistry()
        let refresher = SeatUsageRefresher(client: DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            let percent = auth.contains("seat2") ? 50.0 : 10.0
            return try cardFixtureOK(request, cardFixtureJSON(method: method, totalPercent: percent))
        })

        let epoch1 = registry.advance(for: .seat1)
        await refresher.invalidateBinding(seatID: .seat1, epoch: epoch1)

        let commit = await refresher.refresh(
            credential: .init(seatID: .seat2, access: token2),
            bindingEpoch: registry.current(for: .seat2)
        )
        guard case .applied(let report) = commit,
              case .refreshed(let snap)? = report.outcomes[.seat2]
        else {
            return XCTFail("seat2 refresh should apply")
        }
        XCTAssertEqual(snap.period.usage.totalPercentUsed.percent, 50, accuracy: 0.001)

        let stale = await refresher.refresh(
            credential: .init(seatID: .seat1, access: token1),
            bindingEpoch: 0
        )
        XCTAssertEqual(stale, .discarded)
    }
}

private final class CardRefreshStallGate: @unchecked Sendable {
    var servingB = false
    private let lock = NSLock()
    private var hold = false
    private var held = false
    private var released = false

    func armHold() {
        lock.lock()
        hold = true
        held = false
        released = false
        lock.unlock()
    }

    func waitUntilHeld() async {
        while true {
            lock.lock()
            let isHeld = held
            lock.unlock()
            if isHeld { return }
            await Task.yield()
        }
    }

    func waitIfHeld() async {
        lock.lock()
        let shouldHold = hold
        lock.unlock()
        guard shouldHold else { return }
        lock.lock()
        if !held {
            held = true
            lock.unlock()
            while true {
                lock.lock()
                let done = released
                lock.unlock()
                if done { break }
                await Task.yield()
            }
            lock.lock()
            hold = false
            lock.unlock()
            return
        }
        lock.unlock()
    }

    func releaseHold() {
        lock.lock()
        released = true
        lock.unlock()
    }
}

private func cardFixtureOK(_ request: URLRequest, _ json: String) throws -> (Data, URLResponse) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (Data(json.utf8), response)
}

private func cardFixtureJSON(method: String, totalPercent: Double) -> String {
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
