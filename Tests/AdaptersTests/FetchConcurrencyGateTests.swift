import CursorBarAdapters
import CursorBarDomain
import XCTest

final class FetchConcurrencyGateTests: XCTestCase {
    func testPerSeatIsolationRunsAccountsInParallel() async {
        let gate = FetchConcurrencyGate(limit: 1, isolation: .perSeat)
        let inFlight = GateInFlightCounter()
        async let first: Void = gate.withPermit(seatID: .seat1) {
            await inFlight.enter()
            try? await Task.sleep(nanoseconds: 40_000_000)
            await inFlight.leave()
        }
        async let second: Void = gate.withPermit(seatID: .seat2) {
            await inFlight.enter()
            try? await Task.sleep(nanoseconds: 40_000_000)
            await inFlight.leave()
        }
        await first
        await second
        let observed = await inFlight.maxValue
        let gated = await gate.maxObservedInFlight
        XCTAssertEqual(observed, 2)
        XCTAssertGreaterThanOrEqual(gated, 2)
    }

    func testSharedIsolationCapsAcrossSeats() async {
        let gate = FetchConcurrencyGate(limit: 1, isolation: .shared)
        let inFlight = GateInFlightCounter()
        async let first: Void = gate.withPermit(seatID: .seat1) {
            await inFlight.enter()
            try? await Task.sleep(nanoseconds: 40_000_000)
            await inFlight.leave()
        }
        async let second: Void = gate.withPermit(seatID: .seat2) {
            await inFlight.enter()
            try? await Task.sleep(nanoseconds: 40_000_000)
            await inFlight.leave()
        }
        await first
        await second
        let observed = await inFlight.maxValue
        let gated = await gate.maxObservedInFlight
        XCTAssertEqual(observed, 1)
        XCTAssertLessThanOrEqual(gated, 1)
    }
}

private actor GateInFlightCounter {
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
