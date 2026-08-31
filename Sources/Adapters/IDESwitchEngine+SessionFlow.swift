import CursorBarDomain
import Foundation

extension IDESwitchEngine {
    func injectLaunchAndVerify(
        context: SwitchContext,
        onPhaseChange: (@Sendable (IDESwitchPhase) async -> Void)?
    ) async -> IDESwitchPhase {
        forceQuitContext = nil
        guard context.generation == activeGeneration else { return phase }
        guard let plan = pendingPlan else {
            _ = apply(.failed(.injectFailed(context.seatID)))
            await publish(onPhaseChange)
            return phase
        }

        let store = sessionStoreFactory()
        do {
            try persistJournalThenInject(context: context, plan: plan, store: store)
        } catch let error as CursorAuthSessionStore.StoreError {
            let cleared = await clearJournalRequired(
                seatID: context.seatID,
                onPhaseChange: onPhaseChange
            )
            clearEphemeralSessionState()
            if !cleared { return phase }
            _ = apply(.failed(Self.mapStoreFailure(error, seatID: context.seatID)))
            await publish(onPhaseChange)
            return phase
        } catch is AccountSwitchRecoveryJournalError {
            journalHeld = false
            clearEphemeralSessionState()
            _ = apply(.failed(.injectFailed(context.seatID)))
            await publish(onPhaseChange)
            return phase
        } catch {
            let cleared = await clearJournalRequired(
                seatID: context.seatID,
                onPhaseChange: onPhaseChange
            )
            clearEphemeralSessionState()
            if !cleared { return phase }
            _ = apply(.failed(.injectFailed(context.seatID)))
            await publish(onPhaseChange)
            return phase
        }
        _ = apply(.sessionUpdated(context.generation))
        await publish(onPhaseChange)

        do {
            try process.launch(sharedProfile: sharedProfile, homeDirectory: homeDirectory)
            _ = apply(.launchIssued(context.generation))
            await publish(onPhaseChange)
        } catch {
            await restoreWithoutQuit(
                context: context,
                store: store,
                failure: .launchFailed(context.seatID),
                onPhaseChange: onPhaseChange
            )
            return phase
        }

        if await waitForVerified(context: context, plan: plan, store: store) {
            guard context.generation == activeGeneration else { return phase }
            clearEphemeralSessionState()
            await publish(onPhaseChange)
            return phase
        }

        guard context.generation == activeGeneration else { return phase }
        if case .failed = phase {
            await publish(onPhaseChange)
            return phase
        }
        await recoverAfterFailedVerify(context: context, store: store, onPhaseChange: onPhaseChange)
        return phase
    }

    /// Durable order: read backup → save journal → mutate DB. Journal must exist before inject commits.
    private func persistJournalThenInject(
        context: SwitchContext,
        plan: CursorAuthSessionPlan,
        store: any CursorAuthSessionStoring
    ) throws {
        let backup = try store.readBackup(keys: plan.affectedKeys)
        let recovery = PendingAccountSwitchRecovery(
            seatID: context.seatID,
            generation: context.generation,
            backup: backup
        )
        try recoveryJournal.save(recovery)
        journalHeld = true
        rowBackup = backup
        traceJournal("saved", seatID: context.seatID, generation: context.generation)
        do {
            _ = try store.inject(plan: plan)
        } catch {
            rowBackup = nil
            throw error
        }
    }

    private func recoverAfterFailedVerify(
        context: SwitchContext,
        store: any CursorAuthSessionStoring,
        onPhaseChange: (@Sendable (IDESwitchPhase) async -> Void)?
    ) async {
        guard context.generation == activeGeneration else { return }
        recoveryOrigin = .failedVerify

        _ = apply(.beginRecovery(context.generation))
        await publish(onPhaseChange)
        _ = process.requestGracefulQuit()
        _ = apply(.recoveryQuitIssued(context.generation))
        await publish(onPhaseChange)

        let exited = await process.waitUntilMainProcessesExit(timeout: recoveryExitWaitTimeout)
        guard context.generation == activeGeneration else { return }
        if !exited {
            forceQuitContext = context
            _ = apply(.recoveryWaitTimedOut(context.generation))
            await publish(onPhaseChange)
            return
        }

        _ = apply(.recoveryProcessExited(context.generation))
        await publish(onPhaseChange)
        await restoreAndRelaunchPrior(context: context, store: store, onPhaseChange: onPhaseChange)
    }

    private func restoreWithoutQuit(
        context: SwitchContext,
        store: any CursorAuthSessionStoring,
        failure: IDESwitchFailure,
        onPhaseChange: (@Sendable (IDESwitchPhase) async -> Void)?
    ) async {
        guard context.generation == activeGeneration else { return }
        if !ensureRowBackupFromJournal() {
            _ = apply(.failed(.rollbackFailed(context.seatID)))
            await publish(onPhaseChange)
            return
        }
        if let backup = rowBackup {
            do {
                try store.restore(backup)
            } catch {
                _ = apply(.failed(.rollbackFailed(context.seatID)))
                await publish(onPhaseChange)
                return
            }
        }
        let clearedAfterLaunchFail = await clearJournalRequired(
            seatID: context.seatID,
            onPhaseChange: onPhaseChange
        )
        guard clearedAfterLaunchFail else { return }
        clearEphemeralSessionState()
        _ = apply(.failed(failure))
        await publish(onPhaseChange)
    }

    func restoreAndRelaunchPrior(
        context: SwitchContext,
        store: any CursorAuthSessionStoring,
        onPhaseChange: (@Sendable (IDESwitchPhase) async -> Void)?
    ) async {
        guard context.generation == activeGeneration else { return }
        guard case .restoringSession(let restoring) = phase, restoring == context else {
            _ = apply(.failed(.rollbackFailed(context.seatID)))
            await publish(onPhaseChange)
            return
        }
        if !ensureRowBackupFromJournal() {
            _ = apply(.failed(.rollbackFailed(context.seatID)))
            await publish(onPhaseChange)
            return
        }

        if let backup = rowBackup {
            do {
                try store.restore(backup)
            } catch {
                forceQuitContext = nil
                _ = apply(.failed(.rollbackFailed(context.seatID)))
                await publish(onPhaseChange)
                return
            }
        }

        let clearedAfterRestore = await clearJournalRequired(
            seatID: context.seatID,
            onPhaseChange: onPhaseChange
        )
        guard clearedAfterRestore else { return }

        _ = apply(.sessionRestored(context.generation))
        await publish(onPhaseChange)
        do {
            try process.launch(sharedProfile: sharedProfile, homeDirectory: homeDirectory)
        } catch {
            clearEphemeralSessionState()
            forceQuitContext = nil
            recoveryOrigin = nil
            _ = apply(.failed(.launchFailed(context.seatID)))
            await publish(onPhaseChange)
            return
        }
        switch recoveryOrigin {
        case .startupJournal:
            _ = apply(.pendingRecoveryResolved(context.generation))
        case .failedVerify, .none:
            _ = apply(.priorRelaunchFinished(context.generation))
        }
        clearEphemeralSessionState()
        forceQuitContext = nil
        recoveryOrigin = nil
        await publish(onPhaseChange)
    }

    private func waitForVerified(
        context: SwitchContext,
        plan: CursorAuthSessionPlan,
        store: any CursorAuthSessionStoring
    ) async -> Bool {
        let deadline = ContinuousClock.now + verifyTimeout
        var sawProcessReady = false
        var notedUnmatched = false
        var notedUnread = false
        while ContinuousClock.now < deadline {
            guard context.generation == activeGeneration else { return false }

            let processReady = !process.mainCursorPIDs().isEmpty
            if processReady, !sawProcessReady {
                sawProcessReady = true
                _ = apply(.processReady(context.generation))
            }

            if processReady, let identity = try? store.readIdentity() {
                if CursorIDEIdentity.verify(observed: identity, expectedSubject: plan.expectedSubject) {
                    do {
                        try recoveryJournal.clear()
                        journalHeld = false
                        traceJournal("cleared", seatID: context.seatID, generation: context.generation)
                    } catch {
                        traceJournal("clearFailed", seatID: context.seatID, generation: context.generation)
                        _ = apply(.failed(.pendingRecoveryJournalError(context.seatID)))
                        return false
                    }
                    _ = apply(.identityVerified(context.generation))
                } else if !notedUnmatched {
                    notedUnmatched = true
                    traceVerify("identityUnmatched", context: context)
                }
            } else if processReady, !notedUnread {
                notedUnread = true
                traceVerify("identityUnread", context: context)
            }

            if case .ready = phase {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    func clearEphemeralSessionState() {
        pendingPlan = nil
        rowBackup = nil
    }

    private func clearJournalRequired(
        seatID: SeatID,
        onPhaseChange: (@Sendable (IDESwitchPhase) async -> Void)?
    ) async -> Bool {
        do {
            try recoveryJournal.clear()
            if try recoveryJournal.hasPending() {
                journalHeld = true
                forceQuitContext = nil
                _ = apply(.failed(.pendingRecoveryJournalError(seatID)))
                await publish(onPhaseChange)
                return false
            }
            journalHeld = false
            return true
        } catch {
            journalHeld = true
            forceQuitContext = nil
            _ = apply(.failed(.pendingRecoveryJournalError(seatID)))
            await publish(onPhaseChange)
            return false
        }
    }

    static func mapStoreFailure(
        _ error: CursorAuthSessionStore.StoreError,
        seatID: SeatID
    ) -> IDESwitchFailure {
        switch error {
        case .cursorStillRunning, .databaseBusy:
            return .dbBusyOrLocked(seatID)
        case .databaseUnavailable, .malformedSchema, .transactionFailed, .restoreFailed, .liveDatabaseBlocked:
            return .injectFailed(seatID)
        }
    }

    func publish(_ onPhaseChange: (@Sendable (IDESwitchPhase) async -> Void)?) async {
        guard let onPhaseChange else { return }
        await onPhaseChange(phase)
    }

    @discardableResult
    func apply(_ event: IDESwitchEvent) -> Result<IDESwitchPhase, IDESwitchRejectReason> {
        let from = phase
        let result = IDESwitchReducer.reduce(phase: phase, event: event)
        let to: IDESwitchPhase
        let reject: String?
        switch result {
        case .success(let next):
            phase = next
            to = next
            reject = nil
        case .failure(let reason):
            to = from
            reject = reason.traceName
        }
        tracer.record(
            AccountSwitchTraceRecord(
                kind: .reduce,
                seat: to.targetSeatID?.rawValue ?? from.targetSeatID?.rawValue,
                generation: to.traceGeneration ?? from.traceGeneration,
                from: from.traceName,
                to: to.traceName,
                event: event.traceName,
                reject: reject,
                journal: journalHeld ? "held" : nil
            )
        )
        return result
    }

    func traceReject(_ reason: IDESwitchRejectReason, seatID: SeatID) {
        tracer.record(
            AccountSwitchTraceRecord(
                kind: .reject,
                seat: seatID.rawValue,
                from: phase.traceName,
                to: phase.traceName,
                reject: reason.traceName,
                journal: journalHeld ? "held" : nil
            )
        )
    }

    func traceJournal(_ note: String, seatID: SeatID, generation: UInt64) {
        tracer.record(
            AccountSwitchTraceRecord(
                kind: .journal,
                seat: seatID.rawValue,
                generation: generation,
                from: phase.traceName,
                journal: journalHeld ? "held" : "none",
                note: note
            )
        )
    }

    func traceVerify(_ note: String, context: SwitchContext) {
        tracer.record(
            AccountSwitchTraceRecord(
                kind: .verify,
                seat: context.seatID.rawValue,
                generation: context.generation,
                from: phase.traceName,
                note: note
            )
        )
    }

    func traceProcess(_ note: String, seatID: SeatID, generation: UInt64) {
        tracer.record(
            AccountSwitchTraceRecord(
                kind: .process,
                seat: seatID.rawValue,
                generation: generation,
                from: phase.traceName,
                note: note
            )
        )
    }
}
