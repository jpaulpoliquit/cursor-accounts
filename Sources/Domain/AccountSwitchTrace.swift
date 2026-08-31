import Foundation

/// Secret-free switch breadcrumb. Seat IDs only. Never tokens, email, JWT, or backup bytes.
public struct AccountSwitchTraceRecord: Codable, Sendable, Equatable {
    public var at: Date
    public var kind: Kind
    public var seat: String?
    public var generation: UInt64?
    public var from: String
    public var to: String?
    public var event: String?
    public var reject: String?
    public var journal: String?
    public var note: String?

    public enum Kind: String, Codable, Sendable {
        case reduce
        case reject
        case journal
        case verify
        case process
    }

    public init(
        at: Date = Date(),
        kind: Kind,
        seat: String? = nil,
        generation: UInt64? = nil,
        from: String,
        to: String? = nil,
        event: String? = nil,
        reject: String? = nil,
        journal: String? = nil,
        note: String? = nil
    ) {
        self.at = at
        self.kind = kind
        self.seat = seat
        self.generation = generation
        self.from = from
        self.to = to
        self.event = event
        self.reject = reject
        self.journal = journal
        self.note = note
    }
}

public protocol AccountSwitchTracing: Sendable {
    func record(_ record: AccountSwitchTraceRecord)
}

public struct NullAccountSwitchTrace: AccountSwitchTracing {
    public init() {}
    public func record(_ record: AccountSwitchTraceRecord) {}
}

extension IDESwitchPhase {
    public var traceName: String {
        switch self {
        case .idle:
            return "idle"
        case .confirming(let seatID):
            return "confirming:\(seatID.rawValue)"
        case .quitting(let context):
            return "quitting:\(context.seatID.rawValue)#\(context.generation)"
        case .waitingForExit(let context):
            return "waitingForExit:\(context.seatID.rawValue)#\(context.generation)"
        case .updatingSession(let context):
            return "updatingSession:\(context.seatID.rawValue)#\(context.generation)"
        case .launching(let context):
            return "launching:\(context.seatID.rawValue)#\(context.generation)"
        case .verifying(let context, let evidence):
            return "verifying:\(context.seatID.rawValue)#\(context.generation)+p\(evidence.processReady ? 1 : 0)i\(evidence.identityVerified ? 1 : 0)"
        case .recoveringQuit(let context):
            return "recoveringQuit:\(context.seatID.rawValue)#\(context.generation)"
        case .waitingForRecoveryExit(let context):
            return "waitingForRecoveryExit:\(context.seatID.rawValue)#\(context.generation)"
        case .restoringSession(let context):
            return "restoringSession:\(context.seatID.rawValue)#\(context.generation)"
        case .relaunchingPrior(let context):
            return "relaunchingPrior:\(context.seatID.rawValue)#\(context.generation)"
        case .pendingStartupRecovery(let context):
            return "pendingStartupRecovery:\(context.seatID.rawValue)#\(context.generation)"
        case .ready(let seatID):
            return "ready:\(seatID.rawValue)"
        case .failed(let failure):
            return "failed:\(failure.traceName)"
        }
    }

    public var traceGeneration: UInt64? {
        switch self {
        case .idle, .confirming, .ready, .failed:
            return nil
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
            return context.generation
        }
    }
}

extension IDESwitchFailure {
    public var traceName: String {
        switch self {
        case .preflightFailed(let seatID, let reason):
            return "preflightFailed:\(seatID.rawValue):\(reason.traceName)"
        case .quitTimedOut(let seatID):
            return "quitTimedOut:\(seatID.rawValue)"
        case .recoveryQuitTimedOut(let context):
            return "recoveryQuitTimedOut:\(context.seatID.rawValue)#\(context.generation)"
        case .launchFailed(let seatID):
            return "launchFailed:\(seatID.rawValue)"
        case .detectionFailed(let seatID):
            return "detectionFailed:\(seatID.rawValue)"
        case .forceQuitFailed(let seatID):
            return "forceQuitFailed:\(seatID.rawValue)"
        case .dbBusyOrLocked(let seatID):
            return "dbBusyOrLocked:\(seatID.rawValue)"
        case .injectFailed(let seatID):
            return "injectFailed:\(seatID.rawValue)"
        case .verificationFailed(let seatID):
            return "verificationFailed:\(seatID.rawValue)"
        case .rollbackFailed(let seatID):
            return "rollbackFailed:\(seatID.rawValue)"
        case .pendingRecoveryCorrupt:
            return "pendingRecoveryCorrupt"
        case .pendingRecoveryJournalError(let seatID):
            return "pendingRecoveryJournalError:\(seatID.rawValue)"
        }
    }
}

extension AccountSwitchPreflightReason {
    public var traceName: String {
        switch self {
        case .missingCredentials: return "missingCredentials"
        case .identityNotHydrated: return "identityNotHydrated"
        case .refreshFailed: return "refreshFailed"
        case .apiKeyExchangeFailed: return "apiKeyExchangeFailed"
        case .malformedSessionTokens: return "malformedSessionTokens"
        case .planRejected: return "planRejected"
        }
    }
}

extension IDESwitchEvent {
    public var traceName: String {
        switch self {
        case .requestOpen(let seatID):
            return "requestOpen:\(seatID.rawValue)"
        case .confirmationCancelled:
            return "confirmationCancelled"
        case .confirmationAccepted(let confirmed, let generation):
            return "confirmationAccepted:\(confirmed.seatID.rawValue)#\(generation)"
        case .quitIssued(let generation):
            return "quitIssued#\(generation)"
        case .processExited(let generation):
            return "processExited#\(generation)"
        case .waitTimedOut(let generation):
            return "waitTimedOut#\(generation)"
        case .sessionUpdated(let generation):
            return "sessionUpdated#\(generation)"
        case .launchIssued(let generation):
            return "launchIssued#\(generation)"
        case .processReady(let generation):
            return "processReady#\(generation)"
        case .identityVerified(let generation):
            return "identityVerified#\(generation)"
        case .beginRecovery(let generation):
            return "beginRecovery#\(generation)"
        case .recoveryQuitIssued(let generation):
            return "recoveryQuitIssued#\(generation)"
        case .recoveryProcessExited(let generation):
            return "recoveryProcessExited#\(generation)"
        case .recoveryWaitTimedOut(let generation):
            return "recoveryWaitTimedOut#\(generation)"
        case .sessionRestored(let generation):
            return "sessionRestored#\(generation)"
        case .priorRelaunchFinished(let generation):
            return "priorRelaunchFinished#\(generation)"
        case .failed(let failure):
            return "failed:\(failure.traceName)"
        case .forceQuitFinished(let context):
            return "forceQuitFinished:\(context.seatID.rawValue)#\(context.generation)"
        case .resumeLaunch(let context):
            return "resumeLaunch:\(context.seatID.rawValue)#\(context.generation)"
        case .startupPendingRecoveryDetected(let context):
            return "startupPendingRecoveryDetected:\(context.seatID.rawValue)#\(context.generation)"
        case .startupPendingRecoveryCorrupt:
            return "startupPendingRecoveryCorrupt"
        case .beginPendingRestore(let generation):
            return "beginPendingRestore#\(generation)"
        case .pendingRecoveryResolved(let generation):
            return "pendingRecoveryResolved#\(generation)"
        case .acknowledge:
            return "acknowledge"
        }
    }
}

extension IDESwitchRejectReason {
    public var traceName: String {
        switch self {
        case .switchInProgress: return "switchInProgress"
        case .pendingRecoveryOutstanding: return "pendingRecoveryOutstanding"
        }
    }

    public var menuMessage: String {
        switch self {
        case .switchInProgress:
            return "An account switch is already in progress"
        case .pendingRecoveryOutstanding:
            return "Resolve the leftover account switch before starting another"
        }
    }
}
