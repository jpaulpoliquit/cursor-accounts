import Foundation

/// Pure AggregateSnapshot + usage → credential-free AppPresentation.
public enum SeatPresentationProjector {
    public static func project(
        aggregate: AggregateSnapshot,
        usageBySeat: [SeatID: SeatUsageSnapshot],
        identityPolicy: IdentityDisplayPolicy,
        focusedSeatID: SeatID,
        loginPhases: [SeatID: SeatLoginPhase],
        bootstrapPhase: BootstrapPhase,
        usageRefreshPhase: UsageRefreshPhase,
        setHardLimitPhase: SetHardLimitPhase,
        ideSwitchPhase: IDESwitchPhase = .idle,
        desktopBoundSeatID: SeatID? = nil,
        userLabels: [SeatID: SeatUserLabel] = [:]
    ) -> AppPresentation {
        var rosterIDs = aggregate.seats.map(\.seatID)
        for seatID in loginPhases.keys where !rosterIDs.contains(seatID) {
            rosterIDs.append(seatID)
        }
        rosterIDs.sort()

        var labelBySeat: [SeatID: AccountLabel] = [:]
        var connectedUnnamed = Set<SeatID>()
        for seatID in rosterIDs {
            let seat = aggregate.seats.first(where: { $0.seatID == seatID }) ?? .empty(seatID: seatID)
            let source = AccountLabelResolver.Source(
                seatID: seatID,
                email: seat.email,
                displayName: seat.displayName
            )
            let label = AccountLabelResolver.resolve(policy: identityPolicy, source: source)
            labelBySeat[seatID] = label
            let inFlight = loginPhases[seatID]?.isInFlight == true
            let auth: SeatAuthState = inFlight ? .signingIn : seat.auth
            if auth == .signedIn || auth == .needsReauth, case .cursorAccount = label {
                connectedUnnamed.insert(seatID)
            }
        }
        AccountLabelResolver.disambiguate(&labelBySeat, connected: connectedUnnamed)

        let seats = rosterIDs.map { seatID in
            projectSeat(
                seat: aggregate.seats.first(where: { $0.seatID == seatID })
                    ?? .empty(seatID: seatID),
                usage: usageBySeat[seatID],
                identityPolicy: identityPolicy,
                focusedSeatID: focusedSeatID,
                loginPhase: loginPhases[seatID] ?? .idle,
                isDesktopBound: desktopBoundSeatID == seatID,
                label: labelBySeat[seatID] ?? .cursorAccount(disambiguator: nil),
                usageRefreshPhase: usageRefreshPhase,
                userLabel: userLabels[seatID]
            )
        }
        let connectedAccounts = seats.filter(AddAccountPresentation.isConnectedAccount)
        let addAccount = AddAccountPresentation.project(from: seats)
        let worst = MenuAttention.worst(
            among: connectedAccounts.map { (auth: $0.auth, pill: $0.pill) }
        )
        return AppPresentation(
            seats: seats,
            connectedAccounts: connectedAccounts,
            addAccount: addAccount,
            signedInCount: connectedAccounts.count,
            focusedSeatID: focusedSeatID,
            worstAttention: worst,
            identityPolicy: identityPolicy,
            bootstrapPhase: bootstrapPhase,
            usageRefreshPhase: usageRefreshPhase,
            setHardLimitPhase: setHardLimitPhase,
            ideSwitchPhase: ideSwitchPhase,
            desktopBoundSeatID: desktopBoundSeatID
        )
    }

    private static func projectSeat(
        seat: SeatSnapshot,
        usage: SeatUsageSnapshot?,
        identityPolicy: IdentityDisplayPolicy,
        focusedSeatID: SeatID,
        loginPhase: SeatLoginPhase,
        isDesktopBound: Bool,
        label: AccountLabel,
        usageRefreshPhase: UsageRefreshPhase,
        userLabel: SeatUserLabel?
    ) -> SeatPresentation {
        let source = AccountLabelResolver.Source(
            seatID: seat.seatID,
            email: seat.email,
            displayName: seat.displayName
        )
        let revealedEmail = AccountLabelResolver.revealedEmail(
            policy: identityPolicy,
            source: source
        )

        let plan = usage?.plan ?? seat.plan
        let period = usage?.period
        let usagePercents = period?.usage ?? seat.usage
        let onDemandState: OnDemandState?
        if let usage {
            onDemandState = usage.onDemand
        } else {
            onDemandState = seat.onDemand
        }
        let onDemand = onDemandState.map(OnDemandPresentation.init)
        let pill: SeatStatusPill?
        if let usage {
            pill = usage.statusPill
        } else {
            pill = seat.statusPill
        }

        let auth: SeatAuthState
        if loginPhase.isInFlight {
            auth = .signingIn
        } else {
            auth = seat.auth
        }

        let detail = scrubDetail(
            seat.authDetail ?? loginFailureDetail(loginPhase),
            policy: identityPolicy
        )

        return SeatPresentation(
            seatID: seat.seatID,
            label: label,
            revealedEmail: revealedEmail,
            auth: auth,
            planName: plan?.name,
            planPrice: plan?.price,
            planOwner: plan?.planOwner,
            pictureURL: seat.pictureURL,
            resetDate: plan?.billingCycleEnd ?? usagePercents?.resetsAt ?? period?.usage.resetsAt,
            autoPercent: usagePercents?.autoPercentUsed,
            apiPercent: usagePercents?.apiPercentUsed,
            totalPercent: usagePercents?.totalPercentUsed,
            onDemand: onDemand,
            credits: usage?.credits,
            policy: usage?.policy,
            pill: pill,
            authDetail: detail,
            loginPhase: loginPhase,
            isFocused: seat.seatID == focusedSeatID,
            isDesktopBound: isDesktopBound,
            usageLoadState: SeatUsageLoadState.resolve(
                auth: auth,
                hasSnapshot: usage != nil,
                refreshPhase: usageRefreshPhase,
                seatID: seat.seatID
            ),
            identityPolicy: identityPolicy,
            hasUsableIdentity: seat.email != nil || seat.displayName != nil,
            userLabel: userLabel
        )
    }

    private static func loginFailureDetail(_ phase: SeatLoginPhase) -> String? {
        guard case .failed(let failure) = phase else { return nil }
        return failure.surfaceMessage
    }

    /// Errors must stay identity-free under mask; strip @ tokens defensively.
    public static func scrubDetail(_ detail: String?, policy: IdentityDisplayPolicy) -> String? {
        guard let detail else { return nil }
        switch policy {
        case .revealEmail:
            return detail
        case .maskEmail:
            if detail.contains("@") {
                return "Something went wrong with this account"
            }
            return detail
        }
    }
}
