import CursorBarAdapters
import CursorBarDomain
import Foundation

extension AppModel {
    /// Pulls profile photos and team membership from GetMe for connected seats.
    func hydrateSeatProfiles() {
        let credentials = loadSignedInCredentials()
        guard !credentials.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let client = DashboardClient()
            let fetched = await withTaskGroup(of: (SeatID, GetMeProfile?).self) { group in
                for credential in credentials {
                    group.addTask {
                        let profile = try? await client.getMeProfile(access: credential.access)
                        return (credential.seatID, profile)
                    }
                }
                var rows: [(SeatID, GetMeProfile)] = []
                for await (seatID, profile) in group {
                    if let profile {
                        rows.append((seatID, profile))
                    }
                }
                return rows
            }
            var changed = false
            for (seatID, profile) in fetched {
                if self.applyHydratedProfile(seatID: seatID, profile: profile) {
                    changed = true
                }
            }
            if changed {
                self.reproject()
            }
            self.prefetchSeatPictures()
        }
    }

    func prefetchSeatPictures() {
        let urls = Set(
            aggregate.seats.compactMap(\.pictureURL)
                + presentation.connectedAccounts.compactMap(\.pictureURL)
        )
        ProfilePictureLoader.prefetch(Array(urls))
    }

    @discardableResult
    func applyHydratedProfile(seatID: SeatID, profile: GetMeProfile) -> Bool {
        let identity = profile.identity
        persistHydratedProfile(seatID: seatID, identity: identity)
        var changed = false
        let seats = aggregate.seats.map { seat -> SeatSnapshot in
            guard seat.seatID == seatID else { return seat }
            let pictureURL = identity.pictureURL ?? seat.pictureURL
            let plan = patchedPlan(seat.plan, isTeam: identity.isTeamAccount)
            if pictureURL == seat.pictureURL, plan == seat.plan {
                return seat
            }
            changed = true
            return SeatSnapshot(
                seatID: seat.seatID,
                auth: seat.auth,
                email: seat.email,
                displayName: seat.displayName,
                pictureURL: pictureURL,
                plan: plan,
                usage: seat.usage,
                onDemand: seat.onDemand,
                authDetail: seat.authDetail
            )
        }
        if changed {
            aggregate = AggregateSnapshot(seats: seats)
        }
        if identity.isTeamAccount, let usage = usageBySeat[seatID], usage.plan.planOwner != .team {
            usageBySeat[seatID] = SeatUsageSnapshot(
                seatID: usage.seatID,
                plan: patchedPlan(usage.plan, isTeam: true) ?? usage.plan,
                period: usage.period,
                hardLimit: usage.hardLimit,
                credits: usage.credits,
                policy: usage.policy,
                fetchedAt: usage.fetchedAt
            )
            persistUsageCards()
            changed = true
        }
        return changed
    }

    private func persistHydratedProfile(seatID: SeatID, identity: HydratedAccountIdentity) {
        guard let record = try? keychain.load(seatID: seatID) else { return }
        let pictureURL = identity.pictureURL ?? record.pictureURL
        let membershipType = identity.isTeamAccount ? "team" : record.membershipType
        guard pictureURL != record.pictureURL || membershipType != record.membershipType else {
            return
        }
        let updated = StoredSeatRecord(
            seatID: record.seatID,
            identity: record.identity,
            access: record.access,
            refresh: record.refresh,
            email: record.email,
            displayName: record.displayName,
            pictureURL: pictureURL,
            expiresAt: record.expiresAt,
            membershipType: membershipType,
            subscriptionStatus: record.subscriptionStatus,
            apiKey: record.apiKey
        )
        try? keychain.save(updated)
    }

    private func patchedPlan(_ plan: PlanInfo?, isTeam: Bool) -> PlanInfo? {
        guard let plan else { return nil }
        guard isTeam, plan.planOwner != .team else { return plan }
        return PlanInfo(
            name: plan.name,
            includedAmountCents: plan.includedAmountCents,
            price: plan.price,
            billingCycleEnd: plan.billingCycleEnd,
            planOwner: .team
        )
    }
}
