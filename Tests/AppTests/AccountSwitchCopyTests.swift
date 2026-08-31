import CursorBarDomain
import XCTest

final class AccountSwitchCopyTests: XCTestCase {
    func testSwitchAccountCopyAvoidsProfileAndDesktopBoundWording() {
        let seat = SeatPresentation(
            seatID: .seat2,
            label: .displayName(DisplayName("Ada")!),
            revealedEmail: Email("ada@example.com"),
            auth: .signedIn,
            isDesktopBound: true,
            identityPolicy: .maskEmail
        )
        XCTAssertEqual(seat.openCursorAsSeatTitle, "Switch account to Ada…")
        XCTAssertTrue(seat.accessibilityLabel.contains("Active"))
        XCTAssertFalse(seat.openCursorAsSeatTitle.localizedCaseInsensitiveContains("profile"))
        XCTAssertFalse(seat.openCursorAsSeatTitle.localizedCaseInsensitiveContains("open cursor as"))
        XCTAssertFalse(seat.accessibilityLabel.contains("Desktop bound"))
        XCTAssertFalse(seat.menuRow.accessibilityLabel.contains("Desktop bound"))

        let context = SwitchContext(seatID: .seat1, generation: 1)
        XCTAssertEqual(IDESwitchPhase.confirming(.seat1).menuStatusText, "Confirm switch account…")
        XCTAssertEqual(IDESwitchPhase.updatingSession(context).menuStatusText, "Updating Cursor session…")
        XCTAssertNil(IDESwitchPhase.ready(.seat1).menuStatusText)
        XCTAssertEqual(
            IDESwitchRejectReason.pendingRecoveryOutstanding.menuMessage,
            "Resolve the leftover account switch before starting another"
        )
        XCTAssertEqual(
            IDESwitchRejectReason.switchInProgress.menuMessage,
            "An account switch is already in progress"
        )
    }

    func testConfirmationPromptSourceUsesSettingsRemainCopy() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/App/Auth/ConfirmationPrompts.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("Switch Cursor to"))
        XCTAssertTrue(source.contains("Settings, extensions, history, and MCP config stay unchanged."))
        XCTAssertTrue(source.contains("Switch Account"))
        XCTAssertTrue(source.contains("Force Quit Cursor?"))
        XCTAssertTrue(
            source.contains(
                "Cursor did not quit after a failed switch; force quitting may discard unsaved work and is required to restore the previous account."
            )
        )
        XCTAssertTrue(
            source.contains(
                "Cursor did not exit in time. Force Quit ends the app immediately, then account switching can continue."
            )
        )
        XCTAssertFalse(source.contains("Open Cursor as"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("user-data-dir"))
    }

    func testRecoveryMenuStatusAndForceQuitPromptKinds() {
        let context = SwitchContext(seatID: .seat2, generation: 1)
        XCTAssertEqual(
            IDESwitchPhase.restoringSession(context).menuStatusText,
            "Restoring previous account…"
        )
        XCTAssertEqual(
            IDESwitchPhase.failed(.recoveryQuitTimedOut(context)).forceQuitPrompt,
            .restorePreviousAccountAfterFailedSwitch
        )
        XCTAssertEqual(
            IDESwitchPhase.failed(.quitTimedOut(.seat2)).forceQuitPrompt,
            .continueAccountSwitch
        )
    }
}
