import CursorBarAdapters
import CursorBarDomain
import Foundation

extension AppModel {
    func persistUsageCards() {
        cardSnapshotStore.write(usageBySeat)
    }

    func pruneUsageCardsToRoster() {
        let ids = Set(aggregate.seats.map(\.seatID))
        usageBySeat = usageBySeat.filter { ids.contains($0.key) }
        persistUsageCards()
    }

    func reproject() {
        var roster = aggregate.seats.map(\.seatID)
        for seatID in seatAuth.loginPhases.keys where !roster.contains(seatID) {
            roster.append(seatID)
        }
        let focused = FocusedSeatPolicy.resolve(stored: focusedSeatID, roster: roster)
        if focused != focusedSeatID, !roster.isEmpty {
            focusedSeatID = focused
            focusStore.save(focused)
        }
        presentation = SeatPresentationProjector.project(
            aggregate: aggregate,
            usageBySeat: usageBySeat,
            identityPolicy: identityPolicy,
            focusedSeatID: focusedSeatID,
            loginPhases: seatAuth.loginPhases,
            bootstrapPhase: bootstrapPhase,
            usageRefreshPhase: usageRefresh.phase,
            setHardLimitPhase: setHardLimitPhase,
            ideSwitchPhase: ideSwitch.phase,
            desktopBoundSeatID: ideSwitch.desktopBoundSeatID,
            userLabels: currentUserLabels()
        )
        publicRosterStore.write(
            aggregate: aggregate,
            userLabels: currentUserLabels(),
            desktopBoundSeatID: ideSwitch.desktopBoundSeatID
        )
    }

    func projectUsage(_ snapshot: SeatUsageSnapshot) {
        let seats = aggregate.seats.map { seat -> SeatSnapshot in
            guard seat.seatID == snapshot.seatID else { return seat }
            return SeatSnapshot(
                seatID: seat.seatID,
                auth: seat.auth,
                email: seat.email,
                displayName: seat.displayName,
                pictureURL: seat.pictureURL,
                plan: snapshot.plan,
                usage: snapshot.period.usage,
                onDemand: snapshot.onDemand,
                authDetail: nil
            )
        }
        aggregate = AggregateSnapshot(seats: seats)
    }

    func invalidateSignedInCredentials() {
        signedInCredentialsValid = false
        signedInCredentials = []
    }

    func signedInCredentialsForTests() -> [SeatUsageRefresher.SeatCredential] {
        loadSignedInCredentials()
    }

    func loadSignedInCredentials() -> [SeatUsageRefresher.SeatCredential] {
        if signedInCredentialsValid {
            return signedInCredentials
        }
        let loaded = (try? keychain.loadAll())?.compactMap {
            SeatUsageRefresher.SeatCredential(seatID: $0.seatID, access: $0.access)
        } ?? []
        signedInCredentials = loaded
        signedInCredentialsValid = true
        return loaded
    }

    func usageScopeOptions() -> [(UsageScope, String)] {
        var options: [(UsageScope, String)] = [(.allAccounts, "All Accounts")]
        for seat in presentation.connectedAccounts {
            switch seat.auth {
            case .signedIn, .needsReauth:
                options.append((.account(seat.seatID), seat.label.text))
            case .signedOut, .signingIn:
                continue
            }
        }
        return options
    }

    func performSetOnDemand(seatID: SeatID, mode: OnDemandMode) async {
        setHardLimitPhase = .writing(seatID)
        reproject()
        guard let credential = loadSignedInCredentials().first(where: { $0.seatID == seatID }) else {
            setHardLimitPhase = .failed(seatID, message: "Seat is signed out")
            reproject()
            return
        }
        let result = await refresher.setOnDemand(credential: credential, mode: mode)
        switch result {
        case .success(.applied(let snapshot)):
            usageBySeat[snapshot.seatID] = snapshot
            persistUsageCards()
            projectUsage(snapshot)
            setHardLimitPhase = .succeeded(snapshot)
        case .success(.writtenUnconfirmed(let seatID)):
            setHardLimitPhase = .writtenUnconfirmed(seatID)
            usageRefresh.refresh(seatID: seatID)
        case .failure(let failure):
            setHardLimitPhase = .failed(seatID, message: failure.surfaceMessage)
        }
        reproject()
    }
}
