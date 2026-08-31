import CursorBarDomain
import Foundation

/// Idempotent desktop-session bind. Owns placement rules; no separate importer layer.
public struct BootstrapOrchestrator: Sendable {
    public struct Result: Sendable, Equatable {
        public var phase: BootstrapPhase
        public var aggregate: AggregateSnapshot
        /// Seats deleted during roster reconcile/quarantine. App must drop SeatID-keyed caches.
        public var invalidatedSeatIDs: [SeatID]

        public init(
            phase: BootstrapPhase,
            aggregate: AggregateSnapshot,
            invalidatedSeatIDs: [SeatID] = []
        ) {
            self.phase = phase
            self.aggregate = aggregate
            self.invalidatedSeatIDs = invalidatedSeatIDs
        }
    }

    private let sessionSource: CursorDesktopSessionSource
    private let keychain: any SeatCredentialStore
    private let probe: DashboardSessionProbe

    public init(
        sessionSource: CursorDesktopSessionSource = CursorDesktopSessionSource(),
        keychain: any SeatCredentialStore = SeatKeychainStore(),
        probe: DashboardSessionProbe = DashboardSessionProbe()
    ) {
        self.sessionSource = sessionSource
        self.keychain = keychain
        self.probe = probe
    }

    /// Builds a credential-free shell snapshot from Keychain public fields.
    public func shellSnapshot() throws -> AggregateSnapshot {
        _ = OwnedKeychainMigrator(store: keychain).repairIfNeeded()
        let roster = reconcileRoster(try keychain.loadAll()).roster
        let seats = roster.map { $0.publicSnapshot() }
        return AggregateSnapshot(seats: seats)
    }

    public func run() async throws -> Result {
        try Task.checkCancellation()

        switch OwnedKeychainMigrator(store: keychain).repairIfNeeded() {
        case .notNeeded, .repaired:
            break
        case .failed(let message):
            return Result(
                phase: .settled(.importFailed(message: message)),
                aggregate: .empty
            )
        }

        let roster: [StoredSeatRecord]
        let invalidatedSeatIDs: [SeatID]
        do {
            let reconciled = reconcileRoster(try keychain.loadAll())
            roster = reconciled.roster
            invalidatedSeatIDs = reconciled.invalidatedSeatIDs
        } catch {
            return Result(
                phase: .settled(.importFailed(message: "Could not read saved seats")),
                aggregate: .empty
            )
        }

        var working = AggregateSnapshot(seats: roster.map { $0.publicSnapshot() })

        let imported: ImportedDesktopSession?
        do {
            imported = try sessionSource.load()
        } catch {
            return Result(
                phase: .settled(.importFailed(message: "Could not read Cursor desktop session")),
                aggregate: working,
                invalidatedSeatIDs: invalidatedSeatIDs
            )
        }

        guard let imported else {
            return Result(
                phase: .settled(.noDesktopSession),
                aggregate: working,
                invalidatedSeatIDs: invalidatedSeatIDs
            )
        }

        try Task.checkCancellation()

        let importedProbe = await probe.probe(access: imported.access)
        let period: PeriodUsageProbeResult
        switch importedProbe {
        case .failure(.cancelled):
            throw CancellationError()
        case .failure(let failure):
            if let seatID = matchingSeat(in: roster, identity: imported.identity) {
                working = annotate(working, seatID: seatID, detail: failure.surfaceMessage)
            }
            return Result(
                phase: .settled(.importFailed(message: failure.surfaceMessage)),
                aggregate: working,
                invalidatedSeatIDs: invalidatedSeatIDs
            )
        case .success(let value):
            period = value
        }

        try Task.checkCancellation()

        let existing = roster.first(where: { $0.identity == imported.identity })
        var storedProbeSucceeded = false
        if let existing {
            switch await probe.probe(access: existing.access) {
            case .success:
                storedProbeSucceeded = true
            case .failure(.cancelled):
                throw CancellationError()
            case .failure:
                storedProbeSucceeded = false
            }
        }

        let decision = BindPolicy.decide(
            importedIdentity: imported.identity,
            importedExpiresAt: imported.claims.expiresAt,
            roster: roster,
            storedProbeSucceeded: storedProbeSucceeded
        )

        let seatID = decision.seatID
        let writeTokens = decision.writeTokens
        try Task.checkCancellation()

        let access: AccessToken
        let refresh: RefreshToken
        let expiresAt: Date?
        if writeTokens || existing == nil {
            access = imported.access
            refresh = imported.refresh
            expiresAt = imported.claims.expiresAt
        } else if let existing {
            access = existing.access
            refresh = existing.refresh
            expiresAt = existing.expiresAt
        } else {
            access = imported.access
            refresh = imported.refresh
            expiresAt = imported.claims.expiresAt
        }

        let record = StoredSeatRecord(
            seatID: seatID,
            identity: imported.identity,
            access: access,
            refresh: refresh,
            email: imported.email ?? existing?.email,
            displayName: imported.displayName ?? existing?.displayName,
            expiresAt: expiresAt,
            membershipType: imported.membershipType ?? existing?.membershipType,
            subscriptionStatus: imported.subscriptionStatus ?? existing?.subscriptionStatus
        )

        do {
            try keychain.save(record)
        } catch {
            working = annotate(working, seatID: seatID, detail: "Could not save seat credentials")
            return Result(
                phase: .settled(.importFailed(message: "Could not save seat credentials")),
                aggregate: working,
                invalidatedSeatIDs: invalidatedSeatIDs
            )
        }

        let seatSnapshot = record.publicSnapshot(usage: period.usage)
        working = replace(seat: seatSnapshot, in: working)
        let outcome: BootstrapOutcome
        var invalidated = invalidatedSeatIDs
        if existing == nil {
            outcome = .imported(seatID)
            if !invalidated.contains(seatID) {
                invalidated.append(seatID)
            }
        } else if writeTokens {
            outcome = .refreshed(seatID)
        } else {
            outcome = .kept(seatID)
        }
        return Result(
            phase: .settled(outcome),
            aggregate: working,
            invalidatedSeatIDs: invalidated
        )
    }

    private func matchingSeat(in roster: [StoredSeatRecord], identity: SessionIdentity) -> SeatID? {
        roster.first(where: { $0.identity == identity })?.seatID
    }

    /// Dedupe by JWT sub/email and delete incomplete subject-only bindings from app.cursorbar only.
    private func reconcileRoster(
        _ roster: [StoredSeatRecord]
    ) -> (roster: [StoredSeatRecord], invalidatedSeatIDs: [SeatID]) {
        let plan = SeatRosterReconciler.plan(roster: roster)
        for seatID in plan.quarantineSeatIDs {
            try? keychain.delete(seatID: seatID)
        }
        return (plan.keep, plan.quarantineSeatIDs)
    }

    /// Annotates only a bound seat. Unbound import failures stay on BootstrapOutcome alone.
    private func annotate(_ aggregate: AggregateSnapshot, seatID: SeatID, detail: String) -> AggregateSnapshot {
        let seats = aggregate.seats.map { seat -> SeatSnapshot in
            guard seat.seatID == seatID else { return seat }
            let auth: SeatAuthState
            switch seat.auth {
            case .signedOut:
                auth = .needsReauth
            case .signingIn, .signedIn, .needsReauth:
                auth = seat.auth
            }
            return SeatSnapshot(
                seatID: seat.seatID,
                auth: auth,
                email: seat.email,
                displayName: seat.displayName,
                plan: seat.plan,
                usage: seat.usage,
                onDemand: seat.onDemand,
                authDetail: detail
            )
        }
        return AggregateSnapshot(seats: seats)
    }

    private func replace(seat: SeatSnapshot, in aggregate: AggregateSnapshot) -> AggregateSnapshot {
        if aggregate.seats.contains(where: { $0.seatID == seat.seatID }) {
            return AggregateSnapshot(
                seats: aggregate.seats.map { $0.seatID == seat.seatID ? seat : $0 }
            )
        }
        return AggregateSnapshot(seats: aggregate.seats + [seat])
    }
}
