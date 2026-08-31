@testable import CursorBar
import CursorBarDomain
import XCTest

/// Dashboard card projection coverage runnable without DomainTests compile blockers.
@MainActor
final class DashboardAccountCardProjectionTests: XCTestCase {
    func testOffHidesSpendRow() {
        XCTAssertEqual(
            DashboardOnDemandSpendRow.project(
                OnDemandPresentation(mode: .off, usedCents: AmountCents(cents: 1_00))
            ),
            .hidden
        )
    }

    func testFixedAndUnlimitedSpendRows() {
        let fixed = DashboardOnDemandSpendRow.project(
            OnDemandPresentation(
                mode: .fixed(PositiveDollars(190)!),
                usedCents: AmountCents(cents: 16_068)
            )
        )
        guard case .fixed(let amount, let fraction) = fixed else {
            return XCTFail("expected fixed")
        }
        XCTAssertEqual(amount, "$160.68 / $190")
        XCTAssertEqual(fraction!, 16_068.0 / 19_000.0, accuracy: 0.0001)

        let unlimited = DashboardOnDemandSpendRow.project(
            OnDemandPresentation(
                mode: .unlimited,
                usedCents: AmountCents(cents: 16_068)
            )
        )
        guard case .unlimited(let used) = unlimited else {
            return XCTFail("expected unlimited")
        }
        XCTAssertEqual(used, "$160.68")
        XCTAssertFalse(used!.contains("/"))
    }

    func testMenuPendingDisablesWritesAndKeepsSignOutRoute() {
        let seat = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            onDemand: OnDemandPresentation(mode: .unlimited, usedCents: AmountCents(cents: 50)),
            identityPolicy: .maskEmail
        )
        let pending = DashboardSeatControlsProjection.project(
            seat: seat,
            hardLimitPhase: .writing(.seat1)
        )
        guard case .available(_, let selection, _, let status, let disabled) = pending.onDemand else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(selection, .unlimited)
        XCTAssertEqual(status, "Saving…")
        XCTAssertTrue(disabled)
        XCTAssertTrue(pending.showsAccountActionsMenu)
        XCTAssertEqual(pending.accountActionsAccessibilityLabel, "Account actions for john 5")
    }

    func testRedundantLabelsOmittedFromCardProjection() {
        let seat = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            onDemand: OnDemandPresentation(
                mode: .fixed(PositiveDollars(190)!),
                usedCents: AmountCents(cents: 16_068)
            ),
            pill: .onDemandActive,
            isDesktopBound: true,
            identityPolicy: .maskEmail
        )
        let projected = DashboardSeatControlsProjection.project(
            seat: seat,
            hardLimitPhase: .idle
        )
        XCTAssertNil(projected.statusPill)
        XCTAssertTrue(projected.showsActiveIndicator)
        XCTAssertTrue(projected.cardAccessibilityLabel.contains("Active"))
        XCTAssertFalse(projected.cardAccessibilityLabel.contains("Signed in"))
        XCTAssertFalse(projected.cardAccessibilityLabel.contains("Desktop bound"))
        XCTAssertFalse(projected.cardAccessibilityLabel.contains("Connected"))
        XCTAssertFalse(projected.cardAccessibilityLabel.contains("Account"))
    }

    func testSignOutIntentStillRoutesThroughConfirmationCoordinator() async {
        let gate = CardRecordingGate()
        var signedOut: [SeatID] = []
        let coordinator = ConfirmationCommandCoordinator(gate: gate)
        coordinator.configure(
            currentOnDemandMode: { _ in .off },
            policyForSeat: { _ in nil },
            accountLabel: { _ in "john 5" },
            performSignOut: { signedOut.append($0) },
            performSetOnDemand: { _, _ in }
        )

        coordinator.requestSignOutLocally(seatID: .seat1)
        await Task.yield()
        XCTAssertEqual(coordinator.signOutInvocations, 0)
        XCTAssertTrue(signedOut.isEmpty)

        gate.allowSignOut = true
        coordinator.requestSignOutLocally(seatID: .seat1)
        for _ in 0..<20 {
            if signedOut.count == 1 { break }
            await Task.yield()
        }
        XCTAssertEqual(coordinator.signOutInvocations, 1)
        XCTAssertEqual(signedOut, [.seat1])
    }
}

@MainActor
private final class CardRecordingGate: ConfirmationGate {
    var allowSignOut = false

    func confirmLocalSignOut(accountLabel: String) -> Bool { allowSignOut }
    func confirmOnDemandOff(accountLabel: String) -> Bool { false }
    func confirmOnDemandUnlimited(accountLabel: String) -> Bool { false }
    func promptFixedOnDemand(accountLabel: String, policy: UsagePolicy?) -> OnDemandMode? { nil }
}
