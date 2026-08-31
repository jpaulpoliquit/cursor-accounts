import CursorBarDomain
import Foundation

extension IDESwitchEngine {
    /// Load durable journal after launch. Never auto force-quits. Concurrent calls join one attempt.
    public func bootstrapPendingRecovery(
        onPhaseChange: (@Sendable (IDESwitchPhase) async -> Void)? = nil
    ) async -> IDESwitchPhase {
        if let task = startupRecoveryTask {
            return await task.value
        }
        let task = Task { [self] () -> IDESwitchPhase in
            await self.runBootstrapPendingRecovery(onPhaseChange: onPhaseChange)
            return self.phase
        }
        startupRecoveryTask = task
        let next = await task.value
        if phase.isStartupRecoveryTerminal {
            startupRecoveryTask = nil
        }
        return next
    }

    private func runBootstrapPendingRecovery(
        onPhaseChange: (@Sendable (IDESwitchPhase) async -> Void)?
    ) async {
        let loaded: PendingAccountSwitchRecovery?
        do {
            loaded = try recoveryJournal.load()
        } catch {
            _ = apply(.startupPendingRecoveryCorrupt)
            journalHeld = true
            await publish(onPhaseChange)
            return
        }
        guard let recovery = loaded else {
            do {
                journalHeld = try recoveryJournal.hasPending()
            } catch {
                journalHeld = true
                _ = apply(.startupPendingRecoveryCorrupt)
                await publish(onPhaseChange)
            }
            return
        }

        journalHeld = true
        rowBackup = recovery.backup
        activeGeneration = max(activeGeneration, recovery.generation)
        let context = recovery.switchContext
        forceQuitContext = context
        recoveryOrigin = .startupJournal
        _ = apply(.startupPendingRecoveryDetected(context))
        await publish(onPhaseChange)

        if process.mainCursorPIDs().isEmpty {
            _ = apply(.beginPendingRestore(context.generation))
            await publish(onPhaseChange)
            await restoreAndRelaunchPrior(
                context: context,
                store: sessionStoreFactory(),
                onPhaseChange: onPhaseChange
            )
        }
    }

    /// User-consented restore after a leftover journal was found while Cursor is still running.
    public func continuePendingRestore(
        onPhaseChange: (@Sendable (IDESwitchPhase) async -> Void)? = nil
    ) async -> IDESwitchPhase {
        guard case .pendingStartupRecovery(let context) = phase else { return phase }
        _ = apply(.beginRecovery(context.generation))
        await publish(onPhaseChange)
        _ = process.requestGracefulQuit()
        _ = apply(.recoveryQuitIssued(context.generation))
        await publish(onPhaseChange)

        let exited = await process.waitUntilMainProcessesExit(timeout: recoveryExitWaitTimeout)
        if !exited {
            forceQuitContext = context
            _ = apply(.recoveryWaitTimedOut(context.generation))
            await publish(onPhaseChange)
            return phase
        }

        _ = apply(.recoveryProcessExited(context.generation))
        await publish(onPhaseChange)
        await restoreAndRelaunchPrior(
            context: context,
            store: sessionStoreFactory(),
            onPhaseChange: onPhaseChange
        )
        return phase
    }
}
