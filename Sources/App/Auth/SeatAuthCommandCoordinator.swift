import CursorBarAdapters
import CursorBarDomain
import Foundation

/// Owns per-seat login phase + local sign-out mutation after confirmation.
@MainActor
final class SeatAuthCommandCoordinator {
    private(set) var loginPhases: [SeatID: SeatLoginPhase] = [:]

    private let authEngine: AuthEngine
    private var identityPolicy: () -> IdentityDisplayPolicy = { .maskEmail }
    private var mutateAggregate: ((inout AggregateSnapshot) -> Void) -> Void = { _ in }
    private var removeAccountCaches: (SeatID) async -> Void = { _ in }
    private var warmHistory: (SeatID) -> Void = { _ in }
    private var reloadShell: () -> Void = {}
    private var refreshSeat: (SeatID) -> Void = { _ in }
    private var refreshSeriesAfterPurge: () -> Void = {}
    private var onChange: () -> Void = {}

    init(authEngine: AuthEngine) {
        self.authEngine = authEngine
    }

    func configure(
        identityPolicy: @escaping () -> IdentityDisplayPolicy,
        mutateAggregate: @escaping ((inout AggregateSnapshot) -> Void) -> Void,
        removeAccountCaches: @escaping (SeatID) async -> Void,
        warmHistory: @escaping (SeatID) -> Void = { _ in },
        reloadShell: @escaping () -> Void,
        refreshSeat: @escaping (SeatID) -> Void,
        refreshSeriesAfterPurge: @escaping () -> Void = {},
        onChange: @escaping () -> Void
    ) {
        self.identityPolicy = identityPolicy
        self.mutateAggregate = mutateAggregate
        self.removeAccountCaches = removeAccountCaches
        self.warmHistory = warmHistory
        self.reloadShell = reloadShell
        self.refreshSeat = refreshSeat
        self.refreshSeriesAfterPurge = refreshSeriesAfterPurge
        self.onChange = onChange
    }

    func beginSignIn(seatID: SeatID) {
        Task { await performSignIn(seatID: seatID) }
    }

    func reauthenticate(seatID: SeatID) {
        Task {
            do {
                try await authEngine.signOutLocally(seatID: seatID)
            } catch {
                let detail = SeatPresentationProjector.scrubDetail(
                    "Could not sign out locally",
                    policy: identityPolicy()
                )
                mutateAggregate { aggregate in
                    guard let seat = aggregate.seats.first(where: { $0.seatID == seatID }) else { return }
                    let updated = SeatSnapshot(
                        seatID: seat.seatID,
                        auth: seat.auth,
                        email: seat.email,
                        displayName: seat.displayName,
                        pictureURL: seat.pictureURL,
                        plan: seat.plan,
                        usage: seat.usage,
                        onDemand: seat.onDemand,
                        authDetail: detail
                    )
                    aggregate = AggregateSnapshot(
                        seats: aggregate.seats.map { $0.seatID == seatID ? updated : $0 }
                    )
                }
                onChange()
                return
            }
            await removeAccountCaches(seatID)
            reloadShell()
            await performSignIn(seatID: seatID)
        }
    }

    func cancelSignIn(seatID: SeatID) {
        Task {
            await authEngine.cancelLogin(seatID: seatID)
            loginPhases[seatID] = .failed(.cancelled)
            onChange()
        }
    }

    func performSignOut(seatID: SeatID) async {
        do {
            try await authEngine.signOutLocally(seatID: seatID)
            await removeAccountCaches(seatID)
            loginPhases.removeValue(forKey: seatID)
            reloadShell()
            refreshSeriesAfterPurge()
        } catch {
            let detail = SeatPresentationProjector.scrubDetail(
                "Could not sign out locally",
                policy: identityPolicy()
            )
            mutateAggregate { aggregate in
                guard let seat = aggregate.seats.first(where: { $0.seatID == seatID }) else { return }
                let updated = SeatSnapshot(
                    seatID: seat.seatID,
                    auth: seat.auth,
                    email: seat.email,
                    displayName: seat.displayName,
                    pictureURL: seat.pictureURL,
                    plan: seat.plan,
                    usage: seat.usage,
                    onDemand: seat.onDemand,
                    authDetail: detail
                )
                aggregate = AggregateSnapshot(
                    seats: aggregate.seats.map { $0.seatID == seatID ? updated : $0 }
                )
            }
            onChange()
        }
    }

    private func performSignIn(seatID: SeatID) async {
        let target = await authEngine.resolvedEmptySeat(preferred: seatID)
        loginPhases[target] = .openingBrowser
        markSigningIn(seatID: target)
        onChange()
        let (_, task) = await authEngine.beginEmptySeatLogin(seatID: target) { [weak self] progress in
            Task { @MainActor in
                self?.applyLoginProgress(progress, seatID: target)
            }
        }
        if loginPhases[target]?.isInFlight == true, loginPhases[target] != .finishingSignIn {
            loginPhases[target] = .polling
            onChange()
        }
        let outcome = await task.value
        applyLoginOutcome(outcome, requested: target)
        reloadShell()
        if case .signedIn(let placed) = outcome {
            await removeAccountCaches(placed)
            if placed != target {
                await removeAccountCaches(target)
            }
            refreshSeat(placed)
            warmHistory(placed)
            refreshSeriesAfterPurge()
        }
    }

    private func applyLoginProgress(_ progress: DeviceLoginProgress, seatID: SeatID) {
        switch progress {
        case .polling:
            loginPhases[seatID] = .polling
        case .finishingSignIn:
            loginPhases[seatID] = .finishingSignIn
        }
        markSigningIn(seatID: seatID)
        onChange()
    }

    private func applyLoginOutcome(_ outcome: DeviceLoginOutcome, requested: SeatID) {
        loginPhases = SeatLoginPhase.phases(after: outcome, requested: requested)
    }

    private func markSigningIn(seatID: SeatID) {
        mutateAggregate { aggregate in
            let seats = aggregate.seats.map { seat -> SeatSnapshot in
                guard seat.seatID == seatID else { return seat }
                return SeatSnapshot(
                    seatID: seat.seatID,
                    auth: .signingIn,
                    email: seat.email,
                    displayName: seat.displayName,
                    pictureURL: seat.pictureURL,
                    plan: seat.plan,
                    usage: seat.usage,
                    onDemand: seat.onDemand,
                    authDetail: seat.authDetail
                )
            }
            aggregate = AggregateSnapshot(seats: seats)
        }
    }
}
