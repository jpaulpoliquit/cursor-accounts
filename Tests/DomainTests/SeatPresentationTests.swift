import CursorBarDomain
import XCTest

final class SeatPresentationTests: XCTestCase {
    func testMaskPresentationCannotCarryRevealedEmail() {
        let seat = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            revealedEmail: Email("user@example.com"),
            auth: .signedIn,
            autoPercent: PercentUsed(unchecked: 68),
            apiPercent: PercentUsed(unchecked: 100),
            onDemand: OnDemandPresentation(
                mode: .fixed(PositiveDollars(190)!),
                usedCents: AmountCents(cents: 12_620)
            ),
            identityPolicy: .maskEmail
        )
        XCTAssertNil(seat.revealedEmail)
        XCTAssertEqual(seat.onDemand?.spendLine, "$126.20 / $190")
        XCTAssertTrue(seat.accessibilityLabel.contains("$126.20 / $190"))
        XCTAssertFalse(seat.accessibilityLabel.contains("@"))
        XCTAssertFalse(seat.rootMenuTitle.contains("@"))
        XCTAssertFalse(seat.rootMenuTitle.contains("Included usage"))
        XCTAssertFalse(seat.rootMenuTitle.contains("Auto "))
        XCTAssertFalse(seat.rootMenuTitle.contains("API "))
        XCTAssertFalse(seat.rootMenuTitle.contains("Seat 1"))
        XCTAssertTrue(seat.rootMenuTitle.contains("\(UsagePoolLabel.cursorModels.compactTitle) 68%"))
        XCTAssertTrue(seat.rootMenuTitle.contains("\(UsagePoolLabel.otherModels.compactTitle) 100%"))
        XCTAssertTrue(seat.accessibilityLabel.contains(UsagePoolLabel.cursorModels.title))
        XCTAssertTrue(seat.accessibilityLabel.contains(UsagePoolLabel.otherModels.title))
    }

    func testRevealKeepsSecondaryEmail() {
        let email = Email("user@example.com")!
        let seat = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            revealedEmail: email,
            auth: .signedIn,
            identityPolicy: .revealEmail
        )
        XCTAssertEqual(seat.revealedEmail, email)
        XCTAssertTrue(seat.accessibilityLabel.contains("@"))
    }

    func testEmptyAndConnectedVisibleCopyHasNoSeatJargon() {
        let empty = SeatPresentation(
            seatID: .seat2,
            label: .cursorAccount(disambiguator: nil),
            auth: .signedOut,
            identityPolicy: .maskEmail
        )
        XCTAssertEqual(empty.rootMenuTitle, "Connect Cursor account")
        XCTAssertEqual(empty.dashboardTitle, "Connect Cursor account")
        XCTAssertFalse(empty.rootMenuTitle.contains("Seat"))
        XCTAssertFalse(empty.dashboardTitle.contains("Seat"))
        XCTAssertFalse(empty.accessibilityLabel.contains("Seat 2"))
        XCTAssertTrue(empty.accessibilityLabel.contains("account 2"))

        let connected = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            planName: "ultra",
            autoPercent: PercentUsed(unchecked: 81),
            apiPercent: PercentUsed(unchecked: 100),
            onDemand: OnDemandPresentation(
                mode: .fixed(PositiveDollars(190)!),
                usedCents: AmountCents(cents: 12_620)
            ),
            pill: .onDemandActive,
            isFocused: true,
            identityPolicy: .maskEmail
        )
        XCTAssertEqual(
            connected.rootMenuTitle,
            "john 5 · Cursor 81% · Other 100% · On-demand"
        )
        XCTAssertEqual(
            connected.focusedSummaryLine,
            "john 5 · Ultra"
        )
        XCTAssertEqual(connected.onDemand?.spendLine, "$126.20 / $190")
        XCTAssertEqual(connected.dashboardTitle, "john 5")
        XCTAssertFalse(connected.rootMenuTitle.contains("Desktop"))
        XCTAssertFalse(connected.rootMenuTitle.contains("Seat"))
    }

    func testTeamLabelUsesPlanOwnerOrPlanName() {
        let stripe = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("ada")!),
            auth: .signedIn,
            planName: "Ultra",
            planOwner: .personal,
            identityPolicy: .maskEmail
        )
        XCTAssertFalse(stripe.isTeamAccount)

        let teamOwner = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("ada")!),
            auth: .signedIn,
            planName: "Ultra",
            planOwner: .team,
            identityPolicy: .maskEmail
        )
        XCTAssertTrue(teamOwner.isTeamAccount)
        XCTAssertEqual(teamOwner.planBadgeTitle, "Ultra")

        let namedTeam = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("ada")!),
            auth: .signedIn,
            planName: "team",
            identityPolicy: .maskEmail
        )
        XCTAssertTrue(namedTeam.isTeamAccount)
    }

    func testAggregateLineIsConcise() {
        let presentation = AppPresentation(
            seats: [],
            signedInCount: 1,
            focusedSeatID: .seat1,
            worstAttention: .onDemandActive,
            identityPolicy: .maskEmail,
            bootstrapPhase: .settled(.kept(.seat1)),
            usageRefreshPhase: .idle,
            setHardLimitPhase: .idle
        )
        XCTAssertEqual(presentation.aggregateLine, "1 connected · On-demand")
        XCTAssertEqual(presentation.menuBarLabel, ProductName.display)
        XCTAssertFalse(presentation.aggregateLine.contains("Focus"))
        XCTAssertFalse(presentation.aggregateLine.contains("Seat"))
        XCTAssertFalse(presentation.aggregateLine.contains("/5"))
        XCTAssertFalse(presentation.menuBarLabel.hasPrefix("MC ·"))
    }

    func testMenuBarLabelUsesDesktopBoundUsageAndOnDemandSpend() {
        let seat = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            autoPercent: PercentUsed(unchecked: 68),
            apiPercent: PercentUsed(unchecked: 100),
            onDemand: OnDemandPresentation(
                mode: .fixed(PositiveDollars(190)!),
                usedCents: AmountCents(cents: 12_620)
            ),
            isFocused: true,
            isDesktopBound: true,
            identityPolicy: .maskEmail
        )
        let presentation = AppPresentation(
            seats: [seat],
            signedInCount: 1,
            focusedSeatID: .seat1,
            worstAttention: .onDemandActive,
            identityPolicy: .maskEmail,
            bootstrapPhase: .settled(.kept(.seat1)),
            usageRefreshPhase: .idle,
            setHardLimitPhase: .idle
        )
        XCTAssertEqual(presentation.menuBarLabel, "68 · 100 · $126.20 / $190")
        XCTAssertEqual(
            presentation.menuBarAccessibilityLabel,
            "john 5, Cursor 68 percent, API 100 percent, $126.20 / $190"
        )
        XCTAssertEqual(presentation.menuBarStatusSeat?.seatID, .seat1)
        XCTAssertTrue(seat.onDemand?.isConsuming == true)
        XCTAssertFalse(presentation.menuBarLabel.contains("Cursor"))
        XCTAssertFalse(presentation.menuBarLabel.contains("API"))
        XCTAssertFalse(presentation.menuBarLabel.contains("MC ·"))
    }

    func testMenuAttentionPriority() {
        XCTAssertGreaterThan(MenuAttention.needsReauth, MenuAttention.onDemandActive)
        XCTAssertGreaterThan(MenuAttention.onDemandActive, MenuAttention.exhausted)
        XCTAssertGreaterThan(MenuAttention.exhausted, MenuAttention.onDemandReady)
        XCTAssertGreaterThan(MenuAttention.onDemandReady, MenuAttention.countOnly)

        let worst = MenuAttention.worst(among: [
            (auth: .signedIn, pill: .onDemandReady),
            (auth: .signedIn, pill: .exhausted),
            (auth: .needsReauth, pill: .onDemandActive),
        ])
        XCTAssertEqual(worst, .needsReauth)

        let active = MenuAttention.worst(among: [
            (auth: .signedIn, pill: .exhausted),
            (auth: .signedIn, pill: .onDemandActive),
        ])
        XCTAssertEqual(active, .onDemandActive)

        let exhausted = MenuAttention.worst(among: [
            (auth: .signedIn, pill: .onDemandReady),
            (auth: .signedIn, pill: .exhausted),
        ])
        XCTAssertEqual(exhausted, .exhausted)
    }

    func testOnDemandAmountValidation() {
        XCTAssertEqual(
            OnDemandAmountValidation.validate(wholeDollars: 0, policy: nil),
            .failure(.notPositiveWholeDollars)
        )
        let ok = OnDemandAmountValidation.validate(wholeDollars: 190, policy: nil)
        guard case .success(let dollars) = ok else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(dollars.amount, 190)

        let policy = UsagePolicy(minLimitCents: AmountCents(cents: 500), maxLimitCents: AmountCents(cents: 10_000))
        XCTAssertEqual(
            OnDemandAmountValidation.validate(wholeDollars: 4, policy: policy),
            .failure(.belowPolicyMinimum(5))
        )
        XCTAssertEqual(
            OnDemandAmountValidation.validate(wholeDollars: 101, policy: policy),
            .failure(.abovePolicyMaximum(100))
        )
    }

    func testProjectorMasksEmailAndSplitsPools() {
        let seat = SeatSnapshot(
            seatID: .seat1,
            auth: .signedIn,
            email: Email("user@example.com"),
            displayName: DisplayName("john 5"),
            plan: PlanInfo(name: "ultra", price: "$200/mo"),
            usage: PeriodUsage(
                autoPercentUsed: PercentUsed(unchecked: 68),
                apiPercentUsed: PercentUsed(unchecked: 100),
                totalPercentUsed: PercentUsed(unchecked: 84)
            ),
            onDemand: OnDemandState(
                mode: .fixed(PositiveDollars(190)!),
                individualUsed: AmountCents(cents: 12_620),
                individualLimit: AmountCents(cents: 19_000)
            )
        )
        let presentation = SeatPresentationProjector.project(
            aggregate: AggregateSnapshot(seats: [seat]),
            usageBySeat: [:],
            identityPolicy: .maskEmail,
            focusedSeatID: .seat1,
            loginPhases: [:],
            bootstrapPhase: .settled(.kept(.seat1)),
            usageRefreshPhase: .idle,
            setHardLimitPhase: .idle
        )
        let focused = try! XCTUnwrap(presentation.focusedSeat)
        XCTAssertEqual(focused.label.text, "john 5")
        XCTAssertEqual(focused.dashboardTitle, "john 5")
        XCTAssertNil(focused.revealedEmail)
        XCTAssertEqual(Int(focused.autoPercent!.percent.rounded()), 68)
        XCTAssertEqual(Int(focused.apiPercent!.percent.rounded()), 100)
        XCTAssertEqual(focused.onDemand?.spendLine, "$126.20 / $190")
        XCTAssertEqual(focused.onDemand?.modeLabel, "Fixed $190")
        XCTAssertEqual(focused.pill, .onDemandActive)
        XCTAssertTrue(focused.rootMenuTitle.contains(UsagePoolLabel.cursorModels.compactTitle))
        XCTAssertTrue(focused.rootMenuTitle.contains(UsagePoolLabel.otherModels.compactTitle))
        XCTAssertTrue(focused.rootMenuTitle.contains("On-demand"))
        XCTAssertFalse(focused.rootMenuTitle.contains("Seat"))
        XCTAssertFalse(focused.rootMenuTitle.contains("$126"))
        XCTAssertFalse(focused.accessibilityLabel.contains("@"))
        XCTAssertFalse(presentation.aggregateLine.contains("Seat"))
        XCTAssertEqual(presentation.connectedAccounts.count, 1)
        guard case .available(let title, _) = presentation.addAccount else {
            return XCTFail("expected connect another CTA")
        }
        XCTAssertEqual(title, "Connect another account")
        let dumped = String(describing: presentation)
        XCTAssertFalse(dumped.contains("Included usage"))
        XCTAssertFalse(dumped.contains(" Auto "))
        XCTAssertFalse(focused.focusedSummaryLine?.contains("Auto ") == true)
        XCTAssertFalse(focused.focusedSummaryLine?.contains("API ") == true)
    }

    func testDashboardControlsProjection() {
        let signedOut = SeatPresentation(
            seatID: .seat2,
            label: .cursorAccount(disambiguator: nil),
            auth: .signedOut,
            identityPolicy: .maskEmail
        )
        let out = DashboardSeatControlsProjection.project(
            seat: signedOut,
            hardLimitPhase: .idle
        )
        XCTAssertEqual(out.auth, .signIn)
        XCTAssertEqual(out.onDemand, .hidden)
        XCTAssertFalse(out.showsAccountActionsMenu)
        XCTAssertFalse(out.showsActiveIndicator)
        XCTAssertFalse(out.cardAccessibilityLabel.contains("Signed in"))
        XCTAssertFalse(out.cardAccessibilityLabel.contains("Desktop bound"))

        let signing = SeatPresentation(
            seatID: .seat2,
            label: .cursorAccount(disambiguator: nil),
            auth: .signingIn,
            loginPhase: .polling,
            identityPolicy: .maskEmail
        )
        let inflight = DashboardSeatControlsProjection.project(
            seat: signing,
            hardLimitPhase: .idle
        )
        XCTAssertEqual(inflight.auth, .signingIn(canCancel: true))

        let signedIn = SeatPresentation(
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
        let writing = DashboardSeatControlsProjection.project(
            seat: signedIn,
            hardLimitPhase: .writing(.seat1)
        )
        guard case .available(let spendRow, let selection, let fixedTitle, let status, let disabled) =
            writing.onDemand
        else {
            return XCTFail("expected available on-demand")
        }
        XCTAssertEqual(status, "Saving…")
        XCTAssertTrue(disabled)
        XCTAssertEqual(selection, .fixed)
        XCTAssertEqual(fixedTitle, "Fixed $190")
        guard case .fixed(let amount, let fraction) = spendRow else {
            return XCTFail("expected fixed spend row")
        }
        XCTAssertEqual(amount, "$160.68 / $190")
        XCTAssertEqual(fraction!, 16_068.0 / 19_000.0, accuracy: 0.0001)
        XCTAssertNil(writing.statusPill)
        XCTAssertTrue(writing.showsActiveIndicator)
        XCTAssertEqual(writing.accountActionsAccessibilityLabel, "Account actions for john 5")
        XCTAssertTrue(writing.cardAccessibilityLabel.contains("Active"))
        XCTAssertFalse(writing.cardAccessibilityLabel.contains("Signed in"))
        XCTAssertFalse(writing.cardAccessibilityLabel.contains("Desktop bound"))
        XCTAssertFalse(writing.cardAccessibilityLabel.contains("Account"))
        XCTAssertFalse(writing.cardAccessibilityLabel.contains("Connected"))

        let unconfirmed = DashboardSeatControlsProjection.project(
            seat: signedIn,
            hardLimitPhase: .writtenUnconfirmed(.seat1)
        )
        guard case .available(_, _, _, let refreshStatus, _) = unconfirmed.onDemand else {
            return XCTFail("expected available on-demand")
        }
        XCTAssertEqual(refreshStatus, "Saved; refreshing…")

        let failed = DashboardSeatControlsProjection.project(
            seat: signedIn,
            hardLimitPhase: .failed(.seat1, message: "Denied")
        )
        guard case .available(_, _, _, let failStatus, _) = failed.onDemand else {
            return XCTFail("expected available on-demand")
        }
        XCTAssertEqual(failStatus, "Denied")
    }

    func testScrubDetailRemovesAtUnderMask() {
        let scrubbed = SeatPresentationProjector.scrubDetail(
            "Failed for user@example.com",
            policy: .maskEmail
        )
        XCTAssertEqual(scrubbed, "Something went wrong with this account")
    }

    func testUserLabelWinsDashboardAndMenuTitle() {
        let seat = SeatSnapshot(
            seatID: .seat1,
            auth: .signedIn,
            displayName: DisplayName("john 5")
        )
        let presentation = SeatPresentationProjector.project(
            aggregate: AggregateSnapshot(seats: [seat]),
            usageBySeat: [:],
            identityPolicy: .maskEmail,
            focusedSeatID: .seat1,
            loginPhases: [:],
            bootstrapPhase: .settled(.kept(.seat1)),
            usageRefreshPhase: .idle,
            setHardLimitPhase: .idle,
            userLabels: [.seat1: SeatUserLabel("Work")!]
        )
        let focused = try! XCTUnwrap(presentation.focusedSeat)
        XCTAssertEqual(focused.dashboardTitle, "Work")
        XCTAssertEqual(focused.menuRow.primaryName, "Work")
        XCTAssertEqual(focused.label.text, "john 5")
    }
}
