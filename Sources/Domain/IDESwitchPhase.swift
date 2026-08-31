import Foundation

/// One in-flight switch attempt. Generation makes stale callbacks unrepresentable as progress.
public struct SwitchContext: Codable, Sendable, Equatable, Hashable {
    public let seatID: SeatID
    public let generation: UInt64

    public init(seatID: SeatID, generation: UInt64) {
        self.seatID = seatID
        self.generation = generation
    }
}

/// Accumulated Ready gates. Ready requires both flags for the same verifying context.
public struct VerificationEvidence: Codable, Sendable, Equatable, Hashable {
    public var processReady: Bool
    public var identityVerified: Bool

    public init(processReady: Bool = false, identityVerified: Bool = false) {
        self.processReady = processReady
        self.identityVerified = identityVerified
    }

    public var isSatisfied: Bool {
        processReady && identityVerified
    }
}

/// Which Force Quit confirmation copy/routing to use. Distinct semantics, shared UI entry.
public enum IDEForceQuitPrompt: Sendable, Equatable, Hashable {
    /// Initial switch: Cursor did not exit before session update.
    case continueAccountSwitch
    /// Rollback after failed verify: force quit required before restore can proceed.
    case restorePreviousAccountAfterFailedSwitch
}

/// Typed account-switch failure. Only quit-wait timeouts offer Force Quit.
public enum IDESwitchFailure: Codable, Sendable, Equatable, Hashable {
    case preflightFailed(SeatID, AccountSwitchPreflightReason)
    case quitTimedOut(SeatID)
    case recoveryQuitTimedOut(SwitchContext)
    case launchFailed(SeatID)
    case detectionFailed(SeatID)
    case forceQuitFailed(SeatID)
    case dbBusyOrLocked(SeatID)
    case injectFailed(SeatID)
    case verificationFailed(SeatID)
    case rollbackFailed(SeatID)
    /// Durable journal present but unreadable. Blocks switching; never claims Active.
    case pendingRecoveryCorrupt
    /// Durable journal could not be cleared after restore. Blocks switching.
    case pendingRecoveryJournalError(SeatID)

    public var allowsForceQuit: Bool {
        switch self {
        case .quitTimedOut, .recoveryQuitTimedOut, .forceQuitFailed:
            return true
        case .preflightFailed,
            .launchFailed,
            .detectionFailed,
            .dbBusyOrLocked,
            .injectFailed,
            .verificationFailed,
            .rollbackFailed,
            .pendingRecoveryCorrupt,
            .pendingRecoveryJournalError:
            return false
        }
    }

    public var forceQuitPrompt: IDEForceQuitPrompt? {
        switch self {
        case .quitTimedOut, .forceQuitFailed:
            return .continueAccountSwitch
        case .recoveryQuitTimedOut:
            return .restorePreviousAccountAfterFailedSwitch
        case .preflightFailed,
            .launchFailed,
            .detectionFailed,
            .dbBusyOrLocked,
            .injectFailed,
            .verificationFailed,
            .rollbackFailed,
            .pendingRecoveryCorrupt,
            .pendingRecoveryJournalError:
            return nil
        }
    }

    public var seatID: SeatID? {
        switch self {
        case .preflightFailed(let seatID, _),
            .quitTimedOut(let seatID),
            .launchFailed(let seatID),
            .detectionFailed(let seatID),
            .forceQuitFailed(let seatID),
            .dbBusyOrLocked(let seatID),
            .injectFailed(let seatID),
            .verificationFailed(let seatID),
            .rollbackFailed(let seatID),
            .pendingRecoveryJournalError(let seatID):
            return seatID
        case .recoveryQuitTimedOut(let context):
            return context.seatID
        case .pendingRecoveryCorrupt:
            return nil
        }
    }

    public var menuMessage: String {
        switch self {
        case .preflightFailed(_, let reason):
            return reason.menuMessage
        case .quitTimedOut(let seatID):
            return "Cursor did not quit in time for account \(seatID.displayIndex). Use Force Quit to continue."
        case .recoveryQuitTimedOut(let context):
            return "Cursor did not quit after a failed switch for account \(context.seatID.displayIndex). Force Quit is required to restore the previous account."
        case .launchFailed:
            return "Could not relaunch Cursor for this account"
        case .detectionFailed:
            return "Cursor launched but was not detected as ready"
        case .forceQuitFailed(let seatID):
            return "Force Quit did not exit Cursor for account \(seatID.displayIndex)"
        case .dbBusyOrLocked:
            return "Cursor session database is busy or locked"
        case .injectFailed:
            return "Could not update the Cursor session"
        case .verificationFailed:
            return "Cursor opened but the account could not be verified"
        case .rollbackFailed:
            return "Session update failed and rollback could not restore the prior account"
        case .pendingRecoveryCorrupt:
            return "A previous account switch left unreadable recovery data. Switching is blocked until this is resolved."
        case .pendingRecoveryJournalError:
            return "Could not clear durable switch recovery data after restore"
        }
    }
}

/// Explicit switch-account lifecycle for one shared Cursor profile.
/// Focus/auth/refresh never enter this machine. `ready` requires process + identity.
public enum IDESwitchPhase: Codable, Sendable, Equatable, Hashable {
    case idle
    case confirming(SeatID)
    case quitting(SwitchContext)
    case waitingForExit(SwitchContext)
    case updatingSession(SwitchContext)
    case launching(SwitchContext)
    case verifying(SwitchContext, VerificationEvidence)
    case recoveringQuit(SwitchContext)
    case waitingForRecoveryExit(SwitchContext)
    case restoringSession(SwitchContext)
    case relaunchingPrior(SwitchContext)
    /// Durable journal detected at startup. Blocks new switches until resolved.
    case pendingStartupRecovery(SwitchContext)
    case ready(SeatID)
    case failed(IDESwitchFailure)

    public var targetSeatID: SeatID? {
        switch self {
        case .idle:
            return nil
        case .confirming(let seatID), .ready(let seatID):
            return seatID
        case .quitting(let context),
            .waitingForExit(let context),
            .updatingSession(let context),
            .launching(let context),
            .verifying(let context, _),
            .recoveringQuit(let context),
            .waitingForRecoveryExit(let context),
            .restoringSession(let context),
            .relaunchingPrior(let context),
            .pendingStartupRecovery(let context):
            return context.seatID
        case .failed(let failure):
            return failure.seatID
        }
    }

    public var switchContext: SwitchContext? {
        switch self {
        case .quitting(let context),
            .waitingForExit(let context),
            .updatingSession(let context),
            .launching(let context),
            .verifying(let context, _),
            .recoveringQuit(let context),
            .waitingForRecoveryExit(let context),
            .restoringSession(let context),
            .relaunchingPrior(let context),
            .pendingStartupRecovery(let context):
            return context
        case .failed(.recoveryQuitTimedOut(let context)):
            return context
        case .idle, .confirming, .ready, .failed:
            return nil
        }
    }

    /// Desktop-session import may run. Recovery-outstanding phases keep the Keychain shell only.
    public var allowsDesktopImport: Bool {
        switch self {
        case .idle, .ready:
            return true
        default:
            return false
        }
    }

    /// Terminal startup-recovery attempt. Concurrent callers may join, then the join task may drop.
    public var isStartupRecoveryTerminal: Bool {
        switch self {
        case .idle, .ready:
            return true
        case .failed(.pendingRecoveryCorrupt),
            .failed(.pendingRecoveryJournalError),
            .failed(.recoveryQuitTimedOut):
            return true
        case .pendingStartupRecovery,
            .confirming,
            .quitting,
            .waitingForExit,
            .updatingSession,
            .launching,
            .verifying,
            .recoveringQuit,
            .waitingForRecoveryExit,
            .restoringSession,
            .relaunchingPrior,
            .failed:
            return false
        }
    }

    /// True while process or session operations are in flight or awaiting confirmation.
    public var blocksOtherOpenActions: Bool {
        switch self {
        case .confirming,
            .quitting,
            .waitingForExit,
            .updatingSession,
            .launching,
            .verifying,
            .recoveringQuit,
            .waitingForRecoveryExit,
            .restoringSession,
            .relaunchingPrior,
            .pendingStartupRecovery:
            return true
        case .failed(.recoveryQuitTimedOut), .failed(.pendingRecoveryCorrupt), .failed(.pendingRecoveryJournalError):
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    /// User can drop a leftover journal without quitting Cursor.
    public var allowsKeepCurrentSession: Bool {
        switch self {
        case .pendingStartupRecovery,
            .failed(.pendingRecoveryCorrupt),
            .failed(.pendingRecoveryJournalError):
            return true
        case .idle,
            .confirming,
            .quitting,
            .waitingForExit,
            .updatingSession,
            .launching,
            .verifying,
            .recoveringQuit,
            .waitingForRecoveryExit,
            .restoringSession,
            .relaunchingPrior,
            .ready,
            .failed:
            return false
        }
    }

    public var allowsForceQuit: Bool {
        switch self {
        case .failed(let failure):
            return failure.allowsForceQuit
        case .idle,
            .confirming,
            .quitting,
            .waitingForExit,
            .updatingSession,
            .launching,
            .verifying,
            .recoveringQuit,
            .waitingForRecoveryExit,
            .restoringSession,
            .relaunchingPrior,
            .pendingStartupRecovery,
            .ready:
            return false
        }
    }

    public var forceQuitPrompt: IDEForceQuitPrompt? {
        switch self {
        case .failed(let failure):
            return failure.forceQuitPrompt
        case .idle,
            .confirming,
            .quitting,
            .waitingForExit,
            .updatingSession,
            .launching,
            .verifying,
            .recoveringQuit,
            .waitingForRecoveryExit,
            .restoringSession,
            .relaunchingPrior,
            .pendingStartupRecovery,
            .ready:
            return nil
        }
    }

    public var menuStatusText: String? {
        switch self {
        case .idle:
            return nil
        case .confirming:
            return "Confirm switch account…"
        case .quitting:
            return "Quitting Cursor…"
        case .waitingForExit:
            return "Waiting for Cursor to exit…"
        case .updatingSession:
            return "Updating Cursor session…"
        case .launching:
            return "Relaunching Cursor…"
        case .verifying:
            return "Verifying account…"
        case .pendingStartupRecovery:
            return "Recovering interrupted account switch…"
        case .recoveringQuit, .waitingForRecoveryExit:
            return "Rolling back failed switch…"
        case .restoringSession:
            return "Restoring previous account…"
        case .relaunchingPrior:
            return "Relaunching previous account…"
        case .ready:
            return nil
        case .failed(let failure):
            return failure.menuMessage
        }
    }
}

/// Confirmation token so views cannot restart Cursor without an explicit prompt.
public struct ConfirmedIDEOpen: Sendable, Equatable, Hashable {
    public let seatID: SeatID

    public static func confirmed(seatID: SeatID) -> ConfirmedIDEOpen {
        ConfirmedIDEOpen(seatID: seatID)
    }
}

/// Inputs that drive pure phase transitions. Side effects live outside the reducer.
public enum IDESwitchEvent: Sendable, Equatable {
    case requestOpen(SeatID)
    case confirmationCancelled
    case confirmationAccepted(ConfirmedIDEOpen, generation: UInt64)
    case quitIssued(UInt64)
    case processExited(UInt64)
    case waitTimedOut(UInt64)
    case sessionUpdated(UInt64)
    case launchIssued(UInt64)
    case processReady(UInt64)
    case identityVerified(UInt64)
    case beginRecovery(UInt64)
    case recoveryQuitIssued(UInt64)
    case recoveryProcessExited(UInt64)
    case recoveryWaitTimedOut(UInt64)
    case sessionRestored(UInt64)
    case priorRelaunchFinished(UInt64)
    case failed(IDESwitchFailure)
    /// After confirmed Force Quit. Context selects continue-switch vs restore-prior routing.
    case forceQuitFinished(SwitchContext)
    /// Resume after Force Quit cleared stuck processes on the initial switch path.
    case resumeLaunch(SwitchContext)
    /// Durable journal found after app restart.
    case startupPendingRecoveryDetected(SwitchContext)
    case startupPendingRecoveryCorrupt
    /// Cursor already stopped; begin restore from durable journal.
    case beginPendingRestore(UInt64)
    /// Startup journal restore finished cleanly.
    case pendingRecoveryResolved(UInt64)
    case acknowledge
}
