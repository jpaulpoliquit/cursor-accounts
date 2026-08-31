import CursorBarDomain
import XCTest

final class IDESwitchReducerTests: XCTestCase {
    func testHappyPathRequiresProcessAndIdentityBeforeReady() {
        var phase: IDESwitchPhase = .idle
        let generation: UInt64 = 7
        let context = SwitchContext(seatID: .seat2, generation: generation)

        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .requestOpen(.seat2))))
        XCTAssertEqual(phase, .confirming(.seat2))

        phase = try! XCTUnwrap(
            success(
                IDESwitchReducer.reduce(
                    phase: phase,
                    event: .confirmationAccepted(.confirmed(seatID: .seat2), generation: generation)
                )
            )
        )
        XCTAssertEqual(phase, .quitting(context))

        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .quitIssued(generation))))
        XCTAssertEqual(phase, .waitingForExit(context))

        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .processExited(generation))))
        XCTAssertEqual(phase, .updatingSession(context))

        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .sessionUpdated(generation))))
        XCTAssertEqual(phase, .launching(context))

        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .launchIssued(generation))))
        XCTAssertEqual(phase, .verifying(context, VerificationEvidence()))

        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .processReady(generation))))
        XCTAssertEqual(phase, .verifying(context, VerificationEvidence(processReady: true)))

        let identityOnly = IDESwitchReducer.reduce(
            phase: .verifying(context, VerificationEvidence()),
            event: .identityVerified(generation)
        )
        XCTAssertEqual(
            try! XCTUnwrap(success(identityOnly)),
            .verifying(context, VerificationEvidence(identityVerified: true))
        )

        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .identityVerified(generation))))
        XCTAssertEqual(phase, .ready(.seat2))
    }

    func testStaleGenerationEvidenceIgnored() {
        let context = SwitchContext(seatID: .seat1, generation: 2)
        let phase: IDESwitchPhase = .verifying(
            context,
            VerificationEvidence(processReady: true, identityVerified: false)
        )
        let stale = IDESwitchReducer.reduce(phase: phase, event: .identityVerified(1))
        XCTAssertEqual(try! XCTUnwrap(success(stale)), phase)

        let current = IDESwitchReducer.reduce(phase: phase, event: .identityVerified(2))
        XCTAssertEqual(try! XCTUnwrap(success(current)), .ready(.seat1))
    }

    func testRecoveryPathRequiresForceQuitConfirmationOnTimeout() {
        let context = SwitchContext(seatID: .seat3, generation: 4)
        var phase: IDESwitchPhase = .verifying(context, VerificationEvidence(processReady: true))

        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .beginRecovery(4))))
        XCTAssertEqual(phase, .recoveringQuit(context))

        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .recoveryQuitIssued(4))))
        XCTAssertEqual(phase, .waitingForRecoveryExit(context))

        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .recoveryWaitTimedOut(4))))
        XCTAssertEqual(phase, .failed(.recoveryQuitTimedOut(context)))
        XCTAssertTrue(phase.allowsForceQuit)
        XCTAssertEqual(phase.forceQuitPrompt, .restorePreviousAccountAfterFailedSwitch)

        let afterForceQuit = IDESwitchReducer.reduce(phase: phase, event: .forceQuitFinished(context))
        XCTAssertEqual(try! XCTUnwrap(success(afterForceQuit)), .restoringSession(context))
    }

    func testForceQuitFinishedFromForceQuitFailedResumes() {
        let context = SwitchContext(seatID: .seat3, generation: 2)
        let phase: IDESwitchPhase = .failed(.forceQuitFailed(.seat3))
        let next = IDESwitchReducer.reduce(phase: phase, event: .forceQuitFinished(context))
        XCTAssertEqual(try! XCTUnwrap(success(next)), .idle)
        let resume = IDESwitchReducer.reduce(phase: .idle, event: .resumeLaunch(context))
        XCTAssertEqual(try! XCTUnwrap(success(resume)), .updatingSession(context))
    }

    func testGracefulRecoveryRestoresAndReportsVerificationFailure() {
        let context = SwitchContext(seatID: .seat4, generation: 9)
        var phase: IDESwitchPhase = .waitingForRecoveryExit(context)
        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .recoveryProcessExited(9))))
        XCTAssertEqual(phase, .restoringSession(context))
        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .sessionRestored(9))))
        XCTAssertEqual(phase, .relaunchingPrior(context))
        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .priorRelaunchFinished(9))))
        XCTAssertEqual(phase, .failed(.verificationFailed(.seat4)))
        XCTAssertFalse(phase.allowsForceQuit)
    }

    func testAcknowledgeKeepsRecoveryQuitTimeout() {
        let context = SwitchContext(seatID: .seat2, generation: 3)
        let phase: IDESwitchPhase = .failed(.recoveryQuitTimedOut(context))
        let next = IDESwitchReducer.reduce(phase: phase, event: .acknowledge)
        XCTAssertEqual(try! XCTUnwrap(success(next)), phase)
        XCTAssertTrue(try! XCTUnwrap(success(next)).blocksOtherOpenActions)
    }

    func testAcknowledgeDismissesLeftoverJournalStates() {
        let context = SwitchContext(seatID: .seat1, generation: 4)
        for phase: IDESwitchPhase in [
            .pendingStartupRecovery(context),
            .failed(.pendingRecoveryCorrupt),
            .failed(.pendingRecoveryJournalError(.seat1)),
        ] {
            let next = IDESwitchReducer.reduce(phase: phase, event: .acknowledge)
            XCTAssertEqual(try! XCTUnwrap(success(next)), .idle, "\(phase)")
        }
    }

    func testPendingStartupRecoveryBlocksNewSwitchAndResolvesToIdle() {
        let context = SwitchContext(seatID: .seat1, generation: 8)
        let blocked = IDESwitchReducer.reduce(
            phase: .pendingStartupRecovery(context),
            event: .requestOpen(.seat2)
        )
        guard case .failure(.pendingRecoveryOutstanding) = blocked else {
            return XCTFail("expected pendingRecoveryOutstanding")
        }

        var phase: IDESwitchPhase = .pendingStartupRecovery(context)
        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .beginPendingRestore(8))))
        XCTAssertEqual(phase, .restoringSession(context))
        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .sessionRestored(8))))
        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .pendingRecoveryResolved(8))))
        XCTAssertEqual(phase, .idle)

        let corrupt = IDESwitchReducer.reduce(phase: .idle, event: .startupPendingRecoveryCorrupt)
        XCTAssertEqual(try! XCTUnwrap(success(corrupt)), .failed(.pendingRecoveryCorrupt))
        XCTAssertTrue(IDESwitchPhase.failed(.pendingRecoveryCorrupt).blocksOtherOpenActions)
    }

    func testConfirmingCanBeReplacedBeforeProcessOps() {
        var phase: IDESwitchPhase = .confirming(.seat1)
        phase = try! XCTUnwrap(success(IDESwitchReducer.reduce(phase: phase, event: .requestOpen(.seat3))))
        XCTAssertEqual(phase, .confirming(.seat3))
    }

    func testConcurrentRequestRejectedDuringProcessOps() {
        let context = SwitchContext(seatID: .seat1, generation: 1)
        for phase: IDESwitchPhase in [
            .quitting(context),
            .waitingForExit(context),
            .updatingSession(context),
            .launching(context),
            .verifying(context, VerificationEvidence()),
            .recoveringQuit(context),
            .waitingForRecoveryExit(context),
            .restoringSession(context),
            .relaunchingPrior(context),
        ] {
            let result = IDESwitchReducer.reduce(phase: phase, event: .requestOpen(.seat2))
            guard case .failure(.switchInProgress) = result else {
                return XCTFail("expected reject for \(phase)")
            }
        }
        for phase: IDESwitchPhase in [
            .failed(.recoveryQuitTimedOut(context)),
            .pendingStartupRecovery(context),
            .failed(.pendingRecoveryCorrupt),
            .failed(.pendingRecoveryJournalError(.seat1)),
        ] {
            let result = IDESwitchReducer.reduce(phase: phase, event: .requestOpen(.seat2))
            guard case .failure(.pendingRecoveryOutstanding) = result else {
                return XCTFail("expected pendingRecoveryOutstanding for \(phase)")
            }
        }
    }

    func testForceQuitOnlyForQuitTimeoutKinds() {
        let context = SwitchContext(seatID: .seat4, generation: 1)
        let timeout = IDESwitchReducer.reduce(
            phase: .waitingForExit(context),
            event: .waitTimedOut(1)
        )
        guard case .success(.failed(.quitTimedOut(let seatID))) = timeout else {
            return XCTFail("expected quitTimedOut")
        }
        XCTAssertEqual(seatID, .seat4)
        XCTAssertTrue(IDESwitchPhase.failed(.quitTimedOut(.seat4)).allowsForceQuit)
        XCTAssertEqual(
            IDESwitchPhase.failed(.quitTimedOut(.seat4)).forceQuitPrompt,
            .continueAccountSwitch
        )
        XCTAssertTrue(IDESwitchPhase.failed(.recoveryQuitTimedOut(context)).allowsForceQuit)

        XCTAssertTrue(IDESwitchPhase.failed(.forceQuitFailed(.seat3)).allowsForceQuit)
        XCTAssertEqual(
            IDESwitchPhase.failed(.forceQuitFailed(.seat3)).forceQuitPrompt,
            .continueAccountSwitch
        )

        let nonTimeout: [IDESwitchFailure] = [
            .preflightFailed(.seat1, .refreshFailed),
            .launchFailed(.seat1),
            .detectionFailed(.seat2),
            .dbBusyOrLocked(.seat1),
            .injectFailed(.seat2),
            .verificationFailed(.seat3),
            .rollbackFailed(.seat4),
            .pendingRecoveryCorrupt,
            .pendingRecoveryJournalError(.seat1),
        ]
        for failure in nonTimeout {
            XCTAssertFalse(
                IDESwitchPhase.failed(failure).allowsForceQuit,
                "Force Quit must be false for \(failure)"
            )
        }
        XCTAssertFalse(IDESwitchPhase.waitingForExit(context).allowsForceQuit)
        XCTAssertFalse(IDESwitchPhase.updatingSession(context).allowsForceQuit)
        XCTAssertFalse(IDESwitchPhase.launching(context).allowsForceQuit)
        XCTAssertFalse(IDESwitchPhase.verifying(context, VerificationEvidence()).allowsForceQuit)
        XCTAssertFalse(IDESwitchPhase.ready(.seat1).allowsForceQuit)
        XCTAssertFalse(IDESwitchPhase.idle.allowsForceQuit)
    }

    func testResumeLaunchEntersUpdatingSession() {
        let context = SwitchContext(seatID: .seat3, generation: 5)
        let phase = IDESwitchReducer.reduce(
            phase: .idle,
            event: .resumeLaunch(context)
        )
        XCTAssertEqual(try! XCTUnwrap(success(phase)), .updatingSession(context))
    }

    func testCancelConfirmationReturnsIdle() {
        let phase = IDESwitchReducer.reduce(
            phase: .confirming(.seat1),
            event: .confirmationCancelled
        )
        XCTAssertEqual(try! XCTUnwrap(success(phase)), .idle)
    }

    func testLaunchArgumentsNeverIncludeTokensOrSeatDirs() {
        let home = URL(fileURLWithPath: "/Users/demo", isDirectory: true)
        let shared = SharedCursorProfile.default(homeDirectory: home)
        let args = CursorLaunchArguments.sharedProfileArguments(for: shared, homeDirectory: home)
        XCTAssertEqual(args, [])
        XCTAssertFalse(args.contains { $0.localizedCaseInsensitiveContains("token") })
        XCTAssertFalse(args.contains { $0.contains("Bearer") })
        XCTAssertFalse(args.contains { $0.contains("seat-") })

        let customRoot = URL(
            fileURLWithPath: "/Users/demo/Library/Application Support/CursorCustom",
            isDirectory: true
        )
        let custom = SharedCursorProfile(rootDirectory: customRoot)
        let customArgs = CursorLaunchArguments.sharedProfileArguments(for: custom, homeDirectory: home)
        XCTAssertEqual(customArgs, ["--user-data-dir", customRoot.path])
        XCTAssertFalse(customArgs.contains { $0.localizedCaseInsensitiveContains("token") })
        XCTAssertFalse(customArgs.contains { $0.contains("IDEProfiles") })
    }

    func testSharedProfileDefaultsAndLegacySeatPathsRemain() {
        let home = URL(fileURLWithPath: "/Users/demo", isDirectory: true)
        let shared = SharedCursorProfile.default(homeDirectory: home)
        XCTAssertEqual(shared.rootDirectory.path, "/Users/demo/Library/Application Support/Cursor")
        XCTAssertEqual(
            shared.stateDatabaseURL.path,
            "/Users/demo/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        )
        XCTAssertEqual(
            IDEProfilePaths.legacyDefaultDirectory(for: .seat1, homeDirectory: home).path,
            shared.rootDirectory.path
        )
        XCTAssertEqual(
            IDEProfilePaths.legacyDefaultDirectory(for: .seat2, homeDirectory: home).path,
            "/Users/demo/Library/Application Support/CursorBar/IDEProfiles/seat-2"
        )
    }

    func testPrivacySafeSwitchAccountTitle() {
        let seat = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            revealedEmail: Email("user@example.com"),
            auth: .signedIn,
            identityPolicy: .maskEmail
        )
        XCTAssertEqual(seat.openCursorAsSeatTitle, "Switch account to john 5…")
        XCTAssertFalse(seat.openCursorAsSeatTitle.contains("@"))
        XCTAssertFalse(seat.openCursorAsSeatTitle.contains("Seat"))
        XCTAssertFalse(seat.openCursorAsSeatTitle.localizedCaseInsensitiveContains("profile"))
        XCTAssertFalse(seat.openCursorAsSeatTitle.localizedCaseInsensitiveContains("desktop bound"))
    }

    func testFailureMenuCopyUsesAccountNotSlotOrProfile() {
        let quit = IDESwitchFailure.quitTimedOut(.seat2).menuMessage
        let force = IDESwitchFailure.forceQuitFailed(.seat3).menuMessage
        XCTAssertTrue(quit.contains("account 2"))
        XCTAssertTrue(force.contains("account 3"))
        XCTAssertFalse(quit.localizedCaseInsensitiveContains("slot"))
        XCTAssertFalse(force.localizedCaseInsensitiveContains("slot"))
        XCTAssertFalse(quit.localizedCaseInsensitiveContains("profile"))
        XCTAssertFalse(force.localizedCaseInsensitiveContains("profile"))
    }

    private func success(_ result: Result<IDESwitchPhase, IDESwitchRejectReason>) -> IDESwitchPhase? {
        switch result {
        case .success(let phase):
            return phase
        case .failure:
            return nil
        }
    }
}
