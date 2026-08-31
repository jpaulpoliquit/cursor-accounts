import CursorBarDomain
import Foundation

/// Quit → journal prior rows → inject → launch shared profile → verify identity.
public actor IDESwitchEngine {
    public static let exitWaitTimeout: Duration = .seconds(15)
    public static let verifyTimeout: Duration = .seconds(10)
    public static let recoveryExitWaitTimeout: Duration = .seconds(15)
    public static let forceQuitWaitTimeout: Duration = .seconds(15)

    enum RecoveryOrigin: Sendable {
        case failedVerify
        case startupJournal
    }

    let process: any CursorProcessControlling
    let preparer: any AccountSwitchSessionPreparing
    let sessionStoreFactory: @Sendable () -> any CursorAuthSessionStoring
    let recoveryJournal: any AccountSwitchRecoveryJournaling
    let tracer: any AccountSwitchTracing
    let sharedProfile: SharedCursorProfile
    let homeDirectory: URL
    let exitWaitTimeout: Duration
    let verifyTimeout: Duration
    let recoveryExitWaitTimeout: Duration
    let forceQuitWaitTimeout: Duration

    var phase: IDESwitchPhase = .idle
    var activeGeneration: UInt64 = 0
    var forceQuitContext: SwitchContext?
    var pendingPlan: CursorAuthSessionPlan?
    var rowBackup: AuthRowBackup?
    var recoveryOrigin: RecoveryOrigin?
    var journalHeld = false
    var startupRecoveryTask: Task<IDESwitchPhase, Never>?

    public init(
        process: any CursorProcessControlling = CursorProcessAdapter(),
        preparer: any AccountSwitchSessionPreparing,
        sessionStoreFactory: @escaping @Sendable () -> any CursorAuthSessionStoring,
        recoveryJournal: any AccountSwitchRecoveryJournaling,
        tracer: any AccountSwitchTracing = NullAccountSwitchTrace(),
        sharedProfile: SharedCursorProfile? = nil,
        homeDirectory: URL? = nil,
        exitWaitTimeout: Duration = IDESwitchEngine.exitWaitTimeout,
        verifyTimeout: Duration = IDESwitchEngine.verifyTimeout,
        recoveryExitWaitTimeout: Duration = IDESwitchEngine.recoveryExitWaitTimeout,
        forceQuitWaitTimeout: Duration = IDESwitchEngine.forceQuitWaitTimeout
    ) {
        let home = homeDirectory ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        self.process = process
        self.preparer = preparer
        self.sessionStoreFactory = sessionStoreFactory
        self.recoveryJournal = recoveryJournal
        self.tracer = tracer
        self.sharedProfile = sharedProfile ?? SharedCursorProfile.default(homeDirectory: home)
        self.homeDirectory = home
        self.exitWaitTimeout = exitWaitTimeout
        self.verifyTimeout = verifyTimeout
        self.recoveryExitWaitTimeout = recoveryExitWaitTimeout
        self.forceQuitWaitTimeout = forceQuitWaitTimeout
    }

    /// Production wiring: AuthEngine preflight + shared-profile SQLite store + Keychain journal.
    public init(
        process: any CursorProcessControlling = CursorProcessAdapter(),
        auth: AuthEngine,
        credentialStore: any SeatCredentialStore,
        recoveryJournal: any AccountSwitchRecoveryJournaling = KeychainAccountSwitchRecoveryJournal(),
        tracer: any AccountSwitchTracing = NullAccountSwitchTrace(),
        homeDirectory: URL? = nil,
        exitWaitTimeout: Duration = IDESwitchEngine.exitWaitTimeout,
        verifyTimeout: Duration = IDESwitchEngine.verifyTimeout,
        recoveryExitWaitTimeout: Duration = IDESwitchEngine.recoveryExitWaitTimeout,
        forceQuitWaitTimeout: Duration = IDESwitchEngine.forceQuitWaitTimeout
    ) {
        let home = homeDirectory ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let profile = SharedCursorProfile.default(homeDirectory: home)
        self.process = process
        self.preparer = AuthEngineSessionPreparer(auth: auth, store: credentialStore)
        self.sessionStoreFactory = {
            let guardAdapter = ProcessCursorExitGuard(process: process)
            return CursorAuthSessionStore.forSharedProfile(profile, exitGuard: guardAdapter)
        }
        self.recoveryJournal = recoveryJournal
        self.tracer = tracer
        self.sharedProfile = profile
        self.homeDirectory = home
        self.exitWaitTimeout = exitWaitTimeout
        self.verifyTimeout = verifyTimeout
        self.recoveryExitWaitTimeout = recoveryExitWaitTimeout
        self.forceQuitWaitTimeout = forceQuitWaitTimeout
    }

    public func currentPhase() -> IDESwitchPhase {
        phase
    }

    public func beginRequest(seatID: SeatID) -> Result<IDESwitchPhase, IDESwitchRejectReason> {
        if let reason = rejectIfJournalOutstanding() {
            traceReject(reason, seatID: seatID)
            return .failure(reason)
        }
        return apply(.requestOpen(seatID))
    }

    public func cancelConfirmation() {
        _ = apply(.confirmationCancelled)
        clearEphemeralSessionState()
    }

    public func runConfirmed(
        _ confirmed: ConfirmedIDEOpen,
        onPhaseChange: (@Sendable (IDESwitchPhase) async -> Void)? = nil
    ) async -> IDESwitchPhase {
        if rejectIfJournalOutstanding() != nil {
            if case .confirming = phase {
                _ = apply(.confirmationCancelled)
                promoteHeldJournalIfQuiet()
            }
            await publish(onPhaseChange)
            return phase
        }

        switch await preparer.preparePlan(for: confirmed.seatID) {
        case .failure(let reason):
            _ = apply(.failed(.preflightFailed(confirmed.seatID, reason)))
            await publish(onPhaseChange)
            return phase
        case .success(let plan):
            pendingPlan = plan
        }

        activeGeneration &+= 1
        let generation = activeGeneration
        let context = SwitchContext(seatID: confirmed.seatID, generation: generation)

        switch apply(.confirmationAccepted(confirmed, generation: generation)) {
        case .failure:
            clearEphemeralSessionState()
            return phase
        case .success:
            await publish(onPhaseChange)
        }

        forceQuitContext = context
        let pidCount = process.mainCursorPIDs().count
        let accepted = process.requestGracefulQuit()
        traceProcess("quit pids=\(pidCount) accepted=\(accepted ? 1 : 0)", seatID: context.seatID, generation: generation)
        _ = apply(.quitIssued(generation))
        await publish(onPhaseChange)

        let exited = await process.waitUntilMainProcessesExit(timeout: exitWaitTimeout)
        guard generation == activeGeneration else { return phase }
        if !exited {
            traceProcess(
                "stillRunning pids=\(process.mainCursorPIDs().count)",
                seatID: context.seatID,
                generation: generation
            )
            _ = apply(.waitTimedOut(generation))
            await publish(onPhaseChange)
            return phase
        }
        forceQuitContext = nil
        _ = apply(.processExited(generation))
        await publish(onPhaseChange)
        return await injectLaunchAndVerify(context: context, onPhaseChange: onPhaseChange)
    }

    public func forceQuitAfterTimeout(
        onPhaseChange: (@Sendable (IDESwitchPhase) async -> Void)? = nil
    ) async -> IDESwitchPhase {
        guard phase.allowsForceQuit, let context = forceQuitContext else { return phase }
        let prompt = phase.forceQuitPrompt
        let before = process.mainCursorPIDs().count
        process.forceQuit()
        let exited = await process.waitUntilMainProcessesExit(timeout: forceQuitWaitTimeout)
        let after = process.mainCursorPIDs().count
        traceProcess(
            "forceQuit before=\(before) after=\(after) exited=\(exited ? 1 : 0)",
            seatID: context.seatID,
            generation: context.generation
        )
        guard exited else {
            _ = apply(.failed(.forceQuitFailed(context.seatID)))
            await publish(onPhaseChange)
            return phase
        }

        switch prompt {
        case .continueAccountSwitch:
            _ = apply(.forceQuitFinished(context))
            forceQuitContext = nil
            await publish(onPhaseChange)
            switch apply(.resumeLaunch(context)) {
            case .failure:
                clearEphemeralSessionState()
                return phase
            case .success:
                await publish(onPhaseChange)
                if pendingPlan == nil {
                    switch await preparer.preparePlan(for: context.seatID) {
                    case .failure(let reason):
                        _ = apply(.failed(.preflightFailed(context.seatID, reason)))
                        await publish(onPhaseChange)
                        return phase
                    case .success(let plan):
                        pendingPlan = plan
                    }
                }
                return await injectLaunchAndVerify(context: context, onPhaseChange: onPhaseChange)
            }
        case .restorePreviousAccountAfterFailedSwitch:
            _ = apply(.forceQuitFinished(context))
            forceQuitContext = nil
            await publish(onPhaseChange)
            await restoreAndRelaunchPrior(
                context: context,
                store: sessionStoreFactory(),
                onPhaseChange: onPhaseChange
            )
            return phase
        case .none:
            return phase
        }
    }

    public func acknowledge() {
        switch phase {
        case .failed(.recoveryQuitTimedOut):
            return
        case .failed(.pendingRecoveryCorrupt),
            .failed(.pendingRecoveryJournalError),
            .failed(.rollbackFailed),
            .failed(.injectFailed),
            .pendingStartupRecovery:
            do {
                try recoveryJournal.clear()
                if try recoveryJournal.hasPending() {
                    applyJournalClearFailure()
                    return
                }
                journalHeld = false
            } catch {
                applyJournalClearFailure()
                return
            }
        default:
            break
        }
        _ = apply(.acknowledge)
        forceQuitContext = nil
        clearEphemeralSessionState()
        startupRecoveryTask = nil
    }

    /// Presence plus a command. Callers reject; this is not a pure query.
    func rejectIfJournalOutstanding() -> IDESwitchRejectReason? {
        switch journalPresence() {
        case .none:
            return nil
        case .pending:
            journalHeld = true
            promoteHeldJournalIfQuiet()
            return .pendingRecoveryOutstanding
        case .unreadable:
            journalHeld = true
            _ = apply(.startupPendingRecoveryCorrupt)
            return .pendingRecoveryOutstanding
        }
    }

    private enum JournalPresence {
        case none
        case pending
        case unreadable
    }

    private func journalPresence() -> JournalPresence {
        do {
            if try recoveryJournal.hasPending() {
                journalHeld = true
                return .pending
            }
            journalHeld = false
            return .none
        } catch {
            journalHeld = true
            return .unreadable
        }
    }

    private func applyJournalClearFailure() {
        journalHeld = true
        if let seatID = phase.targetSeatID {
            _ = apply(.failed(.pendingRecoveryJournalError(seatID)))
        } else {
            _ = apply(.startupPendingRecoveryCorrupt)
        }
    }

    func ensureRowBackupFromJournal() -> Bool {
        if rowBackup != nil { return true }
        do {
            guard let recovery = try recoveryJournal.load() else { return false }
            rowBackup = recovery.backup
            return true
        } catch {
            return false
        }
    }

    func promoteHeldJournalIfQuiet() {
        switch phase {
        case .failed(.recoveryQuitTimedOut),
            .failed(.pendingRecoveryCorrupt),
            .failed(.pendingRecoveryJournalError),
            .pendingStartupRecovery:
            return
        case .idle, .ready, .failed:
            break
        default:
            return
        }
        do {
            if let recovery = try recoveryJournal.load() {
                rowBackup = recovery.backup
                activeGeneration = max(activeGeneration, recovery.generation)
                recoveryOrigin = .startupJournal
                _ = apply(.startupPendingRecoveryDetected(recovery.switchContext))
            } else {
                _ = apply(.startupPendingRecoveryCorrupt)
            }
        } catch {
            _ = apply(.startupPendingRecoveryCorrupt)
        }
    }

}
