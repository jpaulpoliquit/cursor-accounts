@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class SeatUsageRefresherTests: XCTestCase {
    func testParallelRefreshAllIsolatesPerSeatFailureAndKeepsStale() async throws {
        let seat1 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat1.sig"))
        let seat2 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat2.sig"))
        nonisolated(unsafe) var setCount = 0

        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if auth.contains("seat2"), method == "GetPlanInfo" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
            return try Self.ok(request, Self.fixtureJSON(method: method, totalPercent: 40))
        }
        let refresher = SeatUsageRefresher(client: client)

        let first = await refresher.refresh(
            credential: .init(seatID: .seat1, access: seat1),
            bindingEpoch: 0
        )
        guard case .applied(let firstReport) = first,
              case .refreshed(let stale)? = firstReport.outcomes[.seat1]
        else {
            return XCTFail("expected seat1 refresh")
        }
        XCTAssertEqual(stale.period.usage.totalPercentUsed.percent, 40, accuracy: 0.001)

        let client2 = DashboardClient { request in
            setCount += 1
            let method = request.url?.lastPathComponent ?? ""
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if auth.contains("seat2"), method == "GetPlanInfo" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
            if auth.contains("seat1") {
                return try Self.ok(request, Self.fixtureJSON(method: method, totalPercent: 55))
            }
            return try Self.ok(request, Self.fixtureJSON(method: method, totalPercent: 10))
        }
        let refresher2 = SeatUsageRefresher(client: client2)
        _ = await refresher2.refresh(credential: .init(seatID: .seat1, access: seat1), bindingEpoch: 0)

        let commit = await refresher2.refreshAll(
            credentials: [
                .init(seatID: .seat1, access: seat1),
                .init(seatID: .seat2, access: seat2),
            ],
            bindingEpochs: [.seat1: 0, .seat2: 0]
        )
        guard case .applied(let report) = commit else {
            return XCTFail("expected applied report")
        }

        guard case .refreshed(let seat1Snap)? = report.outcomes[.seat1] else {
            return XCTFail("seat1 should refresh")
        }
        guard case .failed(let message)? = report.outcomes[.seat2] else {
            return XCTFail("seat2 should fail")
        }
        XCTAssertEqual(seat1Snap.period.usage.totalPercentUsed.percent, 55, accuracy: 0.001)
        XCTAssertFalse(message.contains("seat1"))
        XCTAssertFalse(message.contains("seat2"))
        let known1 = await refresher2.lastKnownSnapshot(for: .seat1)
        let known2 = await refresher2.lastKnownSnapshot(for: .seat2)
        XCTAssertEqual(known1?.period.usage.totalPercentUsed.percent ?? -1, 55, accuracy: 0.001)
        XCTAssertNil(known2)
        XCTAssertGreaterThan(setCount, 0)
    }

    func testRefreshAllGatesSeatConcurrency() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.gate.sig"))
        let inFlight = SeatInFlightCounter()
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetPlanInfo" {
                await inFlight.enter()
                try await Task.sleep(nanoseconds: 25_000_000)
                await inFlight.leave()
            }
            return try Self.ok(request, Self.fixtureJSON(method: method, totalPercent: 10))
        }
        let refresher = SeatUsageRefresher(client: client, maxConcurrentSeats: 2)
        let seats: [SeatID] = [.seat1, .seat2, .seat3, .seat4, .seat5]
        let commit = await refresher.refreshAll(
            credentials: seats.map { .init(seatID: $0, access: token) },
            bindingEpochs: Dictionary(uniqueKeysWithValues: seats.map { ($0, UInt64(0)) })
        )
        guard case .applied = commit else {
            return XCTFail("expected applied")
        }
        let observed = await inFlight.maxValue
        let gated = await refresher.maxObservedSeatInFlight()
        XCTAssertLessThanOrEqual(observed, 2)
        XCTAssertLessThanOrEqual(gated, 2)
        XCTAssertGreaterThan(observed, 1)
    }

    func testSharedGateCapsCombinedInFlightAcrossRefreshers() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.shared.sig"))
        let inFlight = SeatInFlightCounter()
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetPlanInfo" {
                await inFlight.enter()
                try await Task.sleep(nanoseconds: 25_000_000)
                await inFlight.leave()
            }
            return try Self.ok(request, Self.fixtureJSON(method: method, totalPercent: 10))
        }
        let gate = FetchConcurrencyGate(limit: 1)
        let cards = SeatUsageRefresher(client: client, gate: gate)
        let alsoCards = SeatUsageRefresher(client: client, gate: gate)
        async let first = cards.refreshAll(
            credentials: [.init(seatID: .seat1, access: token)],
            bindingEpochs: [.seat1: 0]
        )
        async let second = alsoCards.refreshAll(
            credentials: [.init(seatID: .seat2, access: token)],
            bindingEpochs: [.seat2: 0]
        )
        _ = await first
        _ = await second
        let observed = await inFlight.maxValue
        let gated = await gate.maxObservedInFlight
        XCTAssertLessThanOrEqual(observed, 1)
        XCTAssertLessThanOrEqual(gated, 1)
    }

    func testStaleGenerationDoesNotOverwriteNewerLastKnown() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let gate = StallGate()
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetPlanInfo" {
                await gate.waitIfFirst()
            }
            let percent = await gate.percentForCurrentRequest()
            return try Self.ok(request, Self.fixtureJSON(method: method, totalPercent: percent))
        }
        let refresher = SeatUsageRefresher(client: client)
        let credential = SeatUsageRefresher.SeatCredential(seatID: .seat1, access: token)

        await gate.armFirstHold()
        let slow = Task {
            await refresher.refresh(credential: credential, bindingEpoch: 0)
        }
        await gate.waitUntilFirstHeld()

        await gate.setPercent(90)
        let fast = await refresher.refresh(credential: credential, bindingEpoch: 0)
        guard case .applied(let fastReport) = fast,
              case .refreshed(let newer)? = fastReport.outcomes[.seat1]
        else {
            return XCTFail("fast refresh should apply")
        }
        XCTAssertEqual(newer.period.usage.totalPercentUsed.percent, 90, accuracy: 0.001)

        await gate.setPercent(10)
        await gate.releaseFirst()
        let slowCommit = await slow.value
        XCTAssertEqual(slowCommit, .discarded)

        let known = await refresher.lastKnownSnapshot(for: .seat1)
        XCTAssertEqual(known?.period.usage.totalPercentUsed.percent ?? -1, 90, accuracy: 0.001)
    }

    func testSetHardLimitWriteFailReadSuccessAndWriteSuccessReadFail() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let methods = MethodLog()

        let successClient = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            await methods.append(method)
            if method == "SetHardLimit" {
                return try Self.ok(request, "{}")
            }
            return try Self.ok(request, Self.fixtureJSON(method: method, totalPercent: 12, hardLimit: 40))
        }
        let refresher = SeatUsageRefresher(client: successClient)
        let applied = await refresher.setOnDemand(
            credential: .init(seatID: .seat1, access: token),
            mode: .fixed(PositiveDollars(40)!)
        )
        guard case .success(.applied(let snapshot)) = applied else {
            return XCTFail("expected applied snapshot")
        }
        XCTAssertEqual(snapshot.hardLimit, .fixed(PositiveDollars(40)!))
        let afterApply = await methods.snapshot()
        XCTAssertTrue(afterApply.contains("SetHardLimit"))
        XCTAssertTrue(afterApply.contains("GetHardLimit"))

        await methods.clear()
        let writeFailClient = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            await methods.append(method)
            if method == "SetHardLimit" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 403,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
            return try Self.ok(request, Self.fixtureJSON(method: method, totalPercent: 12, hardLimit: 40))
        }
        let writeFail = await SeatUsageRefresher(client: writeFailClient).setOnDemand(
            credential: .init(seatID: .seat1, access: token),
            mode: .fixed(PositiveDollars(40)!)
        )
        guard case .failure = writeFail else {
            return XCTFail("expected write failure")
        }
        let afterWriteFail = await methods.snapshot()
        let setIndex = afterWriteFail.firstIndex(of: "SetHardLimit")
        let hardLimitAfterSet = setIndex.flatMap { start in
            afterWriteFail[start...].dropFirst().contains("GetHardLimit")
        } ?? false
        XCTAssertFalse(hardLimitAfterSet)

        let readFail = ReadFailFlag()
        let readFailClient = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "SetHardLimit" {
                return try Self.ok(request, "{}")
            }
            if method == "GetHardLimit", await readFail.isOn {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
            return try Self.ok(request, Self.fixtureJSON(method: method, totalPercent: 12, hardLimit: 40))
        }
        let partialRefresher = SeatUsageRefresher(client: readFailClient)
        _ = await partialRefresher.refresh(credential: .init(seatID: .seat1, access: token), bindingEpoch: 0)
        let prior = await partialRefresher.lastKnownSnapshot(for: .seat1)
        XCTAssertNotNil(prior)

        await readFail.turnOn()
        let partial = await partialRefresher.setOnDemand(
            credential: .init(seatID: .seat1, access: token),
            mode: .unlimited
        )
        XCTAssertEqual(partial, .success(.writtenUnconfirmed(.seat1)))
        let known = await partialRefresher.lastKnownSnapshot(for: .seat1)
        XCTAssertEqual(known, prior)
    }

    func testSetHardLimitDeniedWhenPolicyDisallows() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetUsageLimitPolicyStatus" {
                return try Self.ok(request, #"{"canAdjustOnDemand":false,"canConfigureSpendLimit":false}"#)
            }
            if method == "SetHardLimit" {
                XCTFail("must not write when policy denies")
            }
            return try Self.ok(request, Self.fixtureJSON(method: method, totalPercent: 1))
        }
        let refresher = SeatUsageRefresher(client: client)
        let result = await refresher.setOnDemand(
            credential: .init(seatID: .seat1, access: token),
            mode: .off
        )
        XCTAssertEqual(result, .failure(.policyDenied))
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

    private static func fixtureJSON(method: String, totalPercent: Double, hardLimit: Int32 = 0) -> String {
        switch method {
        case "GetPlanInfo":
            return #"{"planInfo":{"planName":"ultra","includedAmountCents":20000,"price":"$200"}}"#
        case "GetCurrentPeriodUsage":
            return """
            {"planUsage":{"autoPercentUsed":1,"apiPercentUsed":2,"totalPercentUsed":\(totalPercent)},"spendLimitUsage":{"individualUsed":"0"}}
            """
        case "GetHardLimit":
            if hardLimit == 0 {
                return #"{"noUsageBasedAllowed":true,"hardLimit":0}"#
            }
            return #"{"noUsageBasedAllowed":false,"hardLimit":\#(hardLimit)}"#
        case "GetCreditGrantsBalance":
            return "{}"
        case "GetUsageLimitPolicyStatus":
            return #"{"canAdjustOnDemand":true,"canConfigureSpendLimit":true}"#
        default:
            return "{}"
        }
    }
}

private actor MethodLog {
    private var methods: [String] = []

    func append(_ method: String) {
        methods.append(method)
    }

    func snapshot() -> [String] { methods }

    func clear() {
        methods.removeAll()
    }
}

private actor ReadFailFlag {
    private var on = false

    var isOn: Bool { on }

    func turnOn() {
        on = true
    }
}

private actor SeatInFlightCounter {
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

/// Holds only the first GetPlanInfo so a newer refresh can commit first.
private actor StallGate {
    private var holdFirst = false
    private var firstHeld = false
    private var firstReleased = false
    private var percent: Double = 40

    func armFirstHold() {
        holdFirst = true
        firstHeld = false
        firstReleased = false
        percent = 40
    }

    func waitUntilFirstHeld() async {
        while !firstHeld {
            await Task.yield()
        }
    }

    func waitIfFirst() async {
        guard holdFirst else { return }
        if !firstHeld {
            firstHeld = true
            while !firstReleased {
                await Task.yield()
            }
            holdFirst = false
            return
        }
    }

    func releaseFirst() {
        firstReleased = true
    }

    func setPercent(_ value: Double) {
        percent = value
    }

    func percentForCurrentRequest() -> Double {
        percent
    }
}
