import CursorBarDomain
import XCTest

final class DashboardOnDemandSpendRowTests: XCTestCase {
    func testOffHidesSpendRow() {
        XCTAssertEqual(
            DashboardOnDemandSpendRow.project(
                OnDemandPresentation(mode: .off, usedCents: AmountCents(cents: 1_00))
            ),
            .hidden
        )
        XCTAssertEqual(DashboardOnDemandSpendRow.project(nil), .hidden)
    }

    func testFixedProjectsUsedLimitAndFraction() {
        let row = DashboardOnDemandSpendRow.project(
            OnDemandPresentation(
                mode: .fixed(PositiveDollars(190)!),
                usedCents: AmountCents(cents: 16_068)
            )
        )
        guard case .fixed(let amount, let fraction) = row else {
            return XCTFail("expected fixed row")
        }
        XCTAssertEqual(amount, "$160.68 / $190")
        XCTAssertEqual(fraction!, 16_068.0 / 19_000.0, accuracy: 0.0001)
        XCTAssertTrue(row.isVisible)
    }

    func testUnlimitedProjectsUsedOnlyWithoutDenominator() {
        let row = DashboardOnDemandSpendRow.project(
            OnDemandPresentation(
                mode: .unlimited,
                usedCents: AmountCents(cents: 16_068)
            )
        )
        guard case .unlimited(let amount) = row else {
            return XCTFail("expected unlimited row")
        }
        XCTAssertEqual(amount, "$160.68")
        XCTAssertFalse(amount!.contains("/"))
        XCTAssertTrue(row.isVisible)

        let bare = DashboardOnDemandSpendRow.project(OnDemandPresentation(mode: .unlimited))
        guard case .unlimited(let missing) = bare else {
            return XCTFail("expected unlimited row")
        }
        XCTAssertNil(missing)
    }

    func testMenuSelectionAndPendingDisable() {
        XCTAssertEqual(DashboardOnDemandMenuSelection(mode: .off), .off)
        XCTAssertEqual(
            DashboardOnDemandMenuSelection(mode: .fixed(PositiveDollars(190)!)),
            .fixed
        )
        XCTAssertEqual(DashboardOnDemandMenuSelection(mode: .unlimited), .unlimited)

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
        guard case .available(let spendRow, let selection, _, let status, let disabled) =
            pending.onDemand
        else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(selection, .unlimited)
        guard case .unlimited(let amount) = spendRow else {
            return XCTFail("expected unlimited spend")
        }
        XCTAssertEqual(amount, "$0.50")
        XCTAssertEqual(status, "Saving…")
        XCTAssertTrue(disabled)
        XCTAssertTrue(pending.showsSignOut)
    }

    func testRedundantPillsDropWhenSpendRowVisible() {
        let fixed = DashboardOnDemandSpendRow.fixed(amountText: "$1 / $2", progressFraction: 0.5)
        XCTAssertNil(
            DashboardSeatControlsProjection.dashboardStatusPill(.onDemandActive, spendRow: fixed)
        )
        XCTAssertNil(
            DashboardSeatControlsProjection.dashboardStatusPill(.onDemandReady, spendRow: fixed)
        )
        XCTAssertEqual(
            DashboardSeatControlsProjection.dashboardStatusPill(.exhausted, spendRow: fixed),
            .exhausted
        )
        XCTAssertEqual(
            DashboardSeatControlsProjection.dashboardStatusPill(
                .onDemandActive,
                spendRow: .hidden
            ),
            .onDemandActive
        )
    }

    func testActiveIndicatorOnlyFromDesktopBound() {
        let inactive = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            isFocused: true,
            isDesktopBound: false,
            identityPolicy: .maskEmail
        )
        XCTAssertFalse(
            DashboardSeatControlsProjection.project(seat: inactive, hardLimitPhase: .idle)
                .showsActiveIndicator
        )

        let active = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            isFocused: false,
            isDesktopBound: true,
            identityPolicy: .maskEmail
        )
        let projected = DashboardSeatControlsProjection.project(
            seat: active,
            hardLimitPhase: .idle
        )
        XCTAssertTrue(projected.showsActiveIndicator)
        XCTAssertTrue(projected.cardAccessibilityLabel.contains("Active"))
        XCTAssertFalse(projected.cardAccessibilityLabel.contains("Desktop bound"))
    }
}
