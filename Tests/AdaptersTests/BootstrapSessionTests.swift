import CursorBarAdapters
import CursorBarDomain
import XCTest

actor RunGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        for waiter in pending {
            waiter.resume()
        }
    }
}

@MainActor
final class BootstrapSessionTests: XCTestCase {
    func testEnsureStartedIsNoOpWhileRunning() async {
        let gate = RunGate()
        nonisolated(unsafe) var runCount = 0

        let session = BootstrapSession(shell: .empty) {
            runCount += 1
            await gate.wait()
            return BootstrapOrchestrator.Result(
                phase: .settled(.noDesktopSession),
                aggregate: .empty
            )
        }

        session.ensureStarted()
        await waitUntil { runCount == 1 }
        XCTAssertEqual(session.phase, .running)
        session.ensureStarted()
        session.ensureStarted()
        XCTAssertEqual(runCount, 1)
        await gate.open()
        await waitForSettled(session)
        XCTAssertEqual(runCount, 1)
        guard case .settled(.noDesktopSession) = session.phase else {
            return XCTFail("expected settled")
        }
    }

    func testEnsureStartedIsNoOpAfterSettledUnlessRefresh() async {
        nonisolated(unsafe) var runCount = 0
        let session = BootstrapSession(shell: .empty) {
            runCount += 1
            return BootstrapOrchestrator.Result(
                phase: .settled(.noDesktopSession),
                aggregate: .empty
            )
        }
        session.ensureStarted()
        await waitForSettled(session)
        XCTAssertEqual(runCount, 1)
        session.ensureStarted()
        XCTAssertEqual(runCount, 1)
        session.refresh()
        await waitForSettled(session)
        XCTAssertEqual(runCount, 2)
    }

    func testCancelInvalidatesGenerationAndKeepsPriorAggregate() async {
        let shellSeat = SeatSnapshot(
            seatID: .seat1,
            auth: .signedIn,
            email: Email("prior@example.com"),
            plan: PlanInfo(name: "ultra"),
            usage: PeriodUsage(
                autoPercentUsed: PercentUsed(unchecked: 1),
                apiPercentUsed: PercentUsed(unchecked: 2),
                totalPercentUsed: PercentUsed(unchecked: 3)
            )
        )
        let shell = AggregateSnapshot(seats: [shellSeat])
        let gate = RunGate()

        let session = BootstrapSession(shell: shell) {
            await gate.wait()
            let polluted = SeatSnapshot(
                seatID: .seat1,
                auth: .signedIn,
                email: Email("stale@example.com"),
                plan: PlanInfo(name: "pro")
            )
            return BootstrapOrchestrator.Result(
                phase: .settled(.imported(.seat1)),
                aggregate: AggregateSnapshot(seats: [polluted])
            )
        }

        session.ensureStarted()
        await waitUntil { session.phase == .running }
        XCTAssertEqual(session.aggregate.seats[0].email?.value, "prior@example.com")
        session.cancel()
        XCTAssertEqual(session.phase, .pending)
        XCTAssertEqual(session.aggregate.seats[0].email?.value, "prior@example.com")
        await gate.open()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(session.aggregate.seats[0].email?.value, "prior@example.com")
        XCTAssertNotEqual(session.phase, .settled(.imported(.seat1)))
    }

    func testStaleGenerationCannotOverwriteNewerRefresh() async {
        let gate = RunGate()
        nonisolated(unsafe) var runs = 0

        let session = BootstrapSession(shell: .empty) {
            runs += 1
            let run = runs
            if run == 1 {
                await gate.wait()
                let stale = SeatSnapshot(
                    seatID: .seat1,
                    auth: .signedIn,
                    email: Email("stale@example.com")
                )
                return BootstrapOrchestrator.Result(
                    phase: .settled(.imported(.seat1)),
                    aggregate: AggregateSnapshot(seats: [stale])
                )
            }
            let fresh = SeatSnapshot(
                seatID: .seat1,
                auth: .signedIn,
                email: Email("fresh@example.com")
            )
            return BootstrapOrchestrator.Result(
                phase: .settled(.kept(.seat1)),
                aggregate: AggregateSnapshot(seats: [fresh])
            )
        }

        session.ensureStarted()
        await waitUntil { runs == 1 }
        session.refresh()
        await waitForSettled(session)
        XCTAssertEqual(session.aggregate.seats[0].email?.value, "fresh@example.com")
        await gate.open()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(session.aggregate.seats[0].email?.value, "fresh@example.com")
        guard case .settled(.kept(.seat1)) = session.phase else {
            return XCTFail("expected kept from newer generation")
        }
    }

    private func waitForSettled(_ session: BootstrapSession) async {
        await waitUntil {
            if case .settled = session.phase { return true }
            return false
        }
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition not met")
    }
}
