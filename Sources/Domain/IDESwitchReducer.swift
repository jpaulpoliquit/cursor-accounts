import Foundation

public enum IDESwitchRejectReason: Error, Sendable, Equatable {
    case switchInProgress
    case pendingRecoveryOutstanding
}

/// Pure reduction. Concurrent opens are rejected once process ops begin; confirming may replace.
/// Automatic force quit is unrepresentable. `ready` requires processReady + identityVerified.
/// Pending durable recovery blocks new switches and Ready.
public enum IDESwitchReducer {
    public static func reduce(
        phase: IDESwitchPhase,
        event: IDESwitchEvent
    ) -> Result<IDESwitchPhase, IDESwitchRejectReason> {
        switch event {
        case .requestOpen(let seatID):
            switch phase {
            case .idle, .ready, .failed(.quitTimedOut), .failed(.preflightFailed),
                .failed(.launchFailed), .failed(.detectionFailed), .failed(.forceQuitFailed),
                .failed(.dbBusyOrLocked), .failed(.injectFailed), .failed(.verificationFailed),
                .failed(.rollbackFailed), .confirming:
                return .success(.confirming(seatID))
            case .failed(.recoveryQuitTimedOut),
                .failed(.pendingRecoveryCorrupt),
                .failed(.pendingRecoveryJournalError),
                .pendingStartupRecovery:
                return .failure(.pendingRecoveryOutstanding)
            case .quitting, .waitingForExit, .updatingSession, .launching, .verifying,
                .recoveringQuit, .waitingForRecoveryExit, .restoringSession, .relaunchingPrior:
                return .failure(.switchInProgress)
            }
        case .confirmationCancelled:
            guard case .confirming = phase else { return .success(phase) }
            return .success(.idle)
        case .confirmationAccepted(let confirmed, let generation):
            guard case .confirming(let seatID) = phase, seatID == confirmed.seatID else {
                return .success(phase)
            }
            return .success(.quitting(SwitchContext(seatID: confirmed.seatID, generation: generation)))
        case .quitIssued(let generation):
            guard case .quitting(let context) = phase, context.generation == generation else {
                return .success(phase)
            }
            return .success(.waitingForExit(context))
        case .processExited(let generation):
            guard case .waitingForExit(let context) = phase, context.generation == generation else {
                return .success(phase)
            }
            return .success(.updatingSession(context))
        case .waitTimedOut(let generation):
            guard case .waitingForExit(let context) = phase, context.generation == generation else {
                return .success(phase)
            }
            return .success(.failed(.quitTimedOut(context.seatID)))
        case .sessionUpdated(let generation):
            guard case .updatingSession(let context) = phase, context.generation == generation else {
                return .success(phase)
            }
            return .success(.launching(context))
        case .launchIssued(let generation):
            guard case .launching(let context) = phase, context.generation == generation else {
                return .success(phase)
            }
            return .success(.verifying(context, VerificationEvidence()))
        case .processReady(let generation):
            return applyVerificationEvidence(phase: phase, generation: generation) { evidence in
                var next = evidence
                next.processReady = true
                return next
            }
        case .identityVerified(let generation):
            return applyVerificationEvidence(phase: phase, generation: generation) { evidence in
                var next = evidence
                next.identityVerified = true
                return next
            }
        case .beginRecovery(let generation):
            switch phase {
            case .verifying(let context, _) where context.generation == generation:
                return .success(.recoveringQuit(context))
            case .pendingStartupRecovery(let context) where context.generation == generation:
                return .success(.recoveringQuit(context))
            default:
                return .success(phase)
            }
        case .recoveryQuitIssued(let generation):
            guard case .recoveringQuit(let context) = phase, context.generation == generation else {
                return .success(phase)
            }
            return .success(.waitingForRecoveryExit(context))
        case .recoveryProcessExited(let generation):
            guard case .waitingForRecoveryExit(let context) = phase, context.generation == generation else {
                return .success(phase)
            }
            return .success(.restoringSession(context))
        case .recoveryWaitTimedOut(let generation):
            guard case .waitingForRecoveryExit(let context) = phase, context.generation == generation else {
                return .success(phase)
            }
            return .success(.failed(.recoveryQuitTimedOut(context)))
        case .sessionRestored(let generation):
            guard case .restoringSession(let context) = phase, context.generation == generation else {
                return .success(phase)
            }
            return .success(.relaunchingPrior(context))
        case .priorRelaunchFinished(let generation):
            guard case .relaunchingPrior(let context) = phase, context.generation == generation else {
                return .success(phase)
            }
            return .success(.failed(.verificationFailed(context.seatID)))
        case .pendingRecoveryResolved(let generation):
            guard case .relaunchingPrior(let context) = phase, context.generation == generation else {
                return .success(phase)
            }
            return .success(.idle)
        case .failed(let failure):
            return .success(.failed(failure))
        case .forceQuitFinished(let context):
            switch phase {
            case .failed(.quitTimedOut(let seatID)) where seatID == context.seatID:
                return .success(.idle)
            case .failed(.forceQuitFailed(let seatID)) where seatID == context.seatID:
                return .success(.idle)
            case .failed(.recoveryQuitTimedOut(let timedOut)) where timedOut == context:
                return .success(.restoringSession(context))
            default:
                return .success(phase)
            }
        case .resumeLaunch(let context):
            switch phase {
            case .idle, .failed:
                return .success(.updatingSession(context))
            case .confirming, .quitting, .waitingForExit, .updatingSession, .launching, .verifying,
                .recoveringQuit, .waitingForRecoveryExit, .restoringSession, .relaunchingPrior,
                .pendingStartupRecovery, .ready:
                return .failure(.switchInProgress)
            }
        case .startupPendingRecoveryDetected(let context):
            switch phase {
            case .idle, .failed:
                return .success(.pendingStartupRecovery(context))
            default:
                return .success(phase)
            }
        case .startupPendingRecoveryCorrupt:
            return .success(.failed(.pendingRecoveryCorrupt))
        case .beginPendingRestore(let generation):
            guard case .pendingStartupRecovery(let context) = phase, context.generation == generation else {
                return .success(phase)
            }
            return .success(.restoringSession(context))
        case .acknowledge:
            switch phase {
            case .failed(.recoveryQuitTimedOut):
                return .success(phase)
            case .failed(.pendingRecoveryCorrupt),
                .failed(.pendingRecoveryJournalError),
                .pendingStartupRecovery:
                return .success(.idle)
            case .ready, .failed:
                return .success(.idle)
            case .idle, .confirming, .quitting, .waitingForExit, .updatingSession, .launching, .verifying,
                .recoveringQuit, .waitingForRecoveryExit, .restoringSession, .relaunchingPrior:
                return .success(phase)
            }
        }
    }

    private static func applyVerificationEvidence(
        phase: IDESwitchPhase,
        generation: UInt64,
        update: (VerificationEvidence) -> VerificationEvidence
    ) -> Result<IDESwitchPhase, IDESwitchRejectReason> {
        guard case .verifying(let context, let evidence) = phase, context.generation == generation else {
            return .success(phase)
        }
        let nextEvidence = update(evidence)
        if nextEvidence.isSatisfied {
            return .success(.ready(context.seatID))
        }
        return .success(.verifying(context, nextEvidence))
    }
}
