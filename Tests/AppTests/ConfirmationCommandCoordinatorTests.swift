@testable import CursorBar
import CursorBarDomain
import XCTest

@MainActor
final class ConfirmationCommandCoordinatorTests: XCTestCase {
    func testCancelDoesNotInvokeMutations() async {
        let gate = FakeGate(signOut: false, off: false, unlimited: false, fixed: nil)
        var signOutSeats: [SeatID] = []
        var setModes: [(SeatID, OnDemandMode)] = []
        let coordinator = ConfirmationCommandCoordinator(gate: gate)
        coordinator.configure(
            currentOnDemandMode: { _ in .off },
            policyForSeat: { _ in nil },
            accountLabel: { _ in "john 5" },
            performSignOut: { seatID in signOutSeats.append(seatID) },
            performSetOnDemand: { seatID, mode in setModes.append((seatID, mode)) }
        )

        coordinator.requestSignOutLocally(seatID: .seat1)
        coordinator.requestSetOnDemand(seatID: .seat2, mode: .unlimited)
        coordinator.requestSetOnDemandFixed(seatID: .seat3)
        await Task.yield()

        XCTAssertEqual(coordinator.signOutInvocations, 0)
        XCTAssertEqual(coordinator.setOnDemandInvocations, 0)
        XCTAssertTrue(signOutSeats.isEmpty)
        XCTAssertTrue(setModes.isEmpty)
    }

    func testConfirmCallsMutationExactlyOnce() async {
        let gate = FakeGate(
            signOut: true,
            off: true,
            unlimited: true,
            fixed: .fixed(PositiveDollars(40)!)
        )
        var signOutSeats: [SeatID] = []
        var setModes: [(SeatID, OnDemandMode)] = []
        let coordinator = ConfirmationCommandCoordinator(gate: gate)
        coordinator.configure(
            currentOnDemandMode: { _ in nil },
            policyForSeat: { _ in nil },
            accountLabel: { "label-\($0.rawValue)" },
            performSignOut: { seatID in signOutSeats.append(seatID) },
            performSetOnDemand: { seatID, mode in setModes.append((seatID, mode)) }
        )

        coordinator.requestSignOutLocally(seatID: .seat1)
        coordinator.requestSetOnDemand(seatID: .seat2, mode: .off)
        coordinator.requestSetOnDemandFixed(seatID: .seat3)

        for _ in 0..<20 {
            if signOutSeats.count == 1, setModes.count == 2 { break }
            await Task.yield()
        }

        XCTAssertEqual(coordinator.signOutInvocations, 1)
        XCTAssertEqual(coordinator.setOnDemandInvocations, 2)
        XCTAssertEqual(signOutSeats, [.seat1])
        XCTAssertEqual(setModes.map(\.0), [.seat2, .seat3])
        XCTAssertEqual(setModes.map(\.1), [.off, .fixed(PositiveDollars(40)!)])
        XCTAssertEqual(gate.seenLabels.count, 3)
        XCTAssertTrue(gate.seenLabels.allSatisfy { $0.hasPrefix("label-") })
    }
}

@MainActor
private final class FakeGate: ConfirmationGate {
    var signOut: Bool
    var off: Bool
    var unlimited: Bool
    var fixed: OnDemandMode?
    private(set) var seenLabels: [String] = []

    init(signOut: Bool, off: Bool, unlimited: Bool, fixed: OnDemandMode?) {
        self.signOut = signOut
        self.off = off
        self.unlimited = unlimited
        self.fixed = fixed
    }

    func confirmLocalSignOut(accountLabel: String) -> Bool {
        seenLabels.append(accountLabel)
        return signOut
    }

    func confirmOnDemandOff(accountLabel: String) -> Bool {
        seenLabels.append(accountLabel)
        return off
    }

    func confirmOnDemandUnlimited(accountLabel: String) -> Bool {
        seenLabels.append(accountLabel)
        return unlimited
    }

    func promptFixedOnDemand(accountLabel: String, policy: UsagePolicy?) -> OnDemandMode? {
        seenLabels.append(accountLabel)
        return fixed
    }
}
