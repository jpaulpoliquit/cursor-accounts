import Foundation

/// Pure Dashboard control chrome. Views render this; they never invent auth/on-demand policy.
public enum DashboardAuthControl: Sendable, Equatable, Hashable {
    case signIn
    case signingIn(canCancel: Bool)
    case reauthenticate
    case signedIn
}

public enum DashboardOnDemandControl: Sendable, Equatable, Hashable {
    case hidden
    case available(
        spendRow: DashboardOnDemandSpendRow,
        menuSelection: DashboardOnDemandMenuSelection,
        fixedMenuTitle: String,
        statusText: String?,
        writesDisabled: Bool
    )
}

public struct DashboardSeatControlsProjection: Sendable, Equatable, Hashable {
    public let auth: DashboardAuthControl
    public let onDemand: DashboardOnDemandControl
    public let showsAccountActionsMenu: Bool
    public let accountActionsAccessibilityLabel: String
    public let showsActiveIndicator: Bool
    public let statusPill: SeatStatusPill?
    /// Card VoiceOver summary without redundant Signed in / Active / Account chrome.
    public let cardAccessibilityLabel: String

    public init(
        auth: DashboardAuthControl,
        onDemand: DashboardOnDemandControl,
        showsAccountActionsMenu: Bool,
        accountActionsAccessibilityLabel: String,
        showsActiveIndicator: Bool,
        statusPill: SeatStatusPill?,
        cardAccessibilityLabel: String
    ) {
        self.auth = auth
        self.onDemand = onDemand
        self.showsAccountActionsMenu = showsAccountActionsMenu
        self.accountActionsAccessibilityLabel = accountActionsAccessibilityLabel
        self.showsActiveIndicator = showsActiveIndicator
        self.statusPill = statusPill
        self.cardAccessibilityLabel = cardAccessibilityLabel
    }

    /// Compatibility for older call sites that only checked sign-out affordance.
    public var showsSignOut: Bool { showsAccountActionsMenu }

    /// Signed-in seats can open the editor unless a write is already in flight.
    public var canPresentOnDemandEditor: Bool {
        if case .available(_, _, _, _, let writesDisabled) = onDemand {
            return !writesDisabled
        }
        return false
    }

    public static func project(
        seat: SeatPresentation,
        hardLimitPhase: SetHardLimitPhase
    ) -> DashboardSeatControlsProjection {
        let auth: DashboardAuthControl
        switch seat.auth {
        case .signedOut:
            auth = .signIn
        case .signingIn:
            auth = .signingIn(canCancel: seat.loginPhase.isInFlight)
        case .needsReauth:
            auth = .reauthenticate
        case .signedIn:
            auth = .signedIn
        }

        let spendRow = DashboardOnDemandSpendRow.project(seat.onDemand)
        let onDemand: DashboardOnDemandControl
        switch seat.auth {
        case .signedIn, .needsReauth:
            let fixedTitle: String
            if case .fixed(let dollars) = seat.onDemand?.mode {
                fixedTitle = "Fixed $\(dollars.amount)"
            } else {
                fixedTitle = "Fixed"
            }
            onDemand = .available(
                spendRow: spendRow,
                menuSelection: DashboardOnDemandMenuSelection(mode: seat.onDemand?.mode),
                fixedMenuTitle: fixedTitle,
                statusText: hardLimitPhase.statusText(for: seat.seatID),
                writesDisabled: hardLimitPhase.disablesWrites(for: seat.seatID)
                    || !seat.policy.allowsDashboardOnDemandEdit
            )
        case .signedOut, .signingIn:
            onDemand = .hidden
        }

        let showsAccountActionsMenu = seat.auth == .signedIn || seat.auth == .needsReauth
        let showsActiveIndicator = seat.isDesktopBound
        return DashboardSeatControlsProjection(
            auth: auth,
            onDemand: onDemand,
            showsAccountActionsMenu: showsAccountActionsMenu,
            accountActionsAccessibilityLabel: "Account actions for \(seat.label.text)",
            showsActiveIndicator: showsActiveIndicator,
            statusPill: Self.dashboardStatusPill(seat.pill, spendRow: spendRow),
            cardAccessibilityLabel: Self.cardAccessibilityLabel(
                seat: seat,
                spendRow: spendRow,
                showsActiveIndicator: showsActiveIndicator
            )
        )
    }

    /// Drop On-demand / Ready pills when the spend row already communicates mode.
    public static func dashboardStatusPill(
        _ pill: SeatStatusPill?,
        spendRow: DashboardOnDemandSpendRow
    ) -> SeatStatusPill? {
        guard let pill else { return nil }
        switch (pill, spendRow) {
        case (.onDemandActive, .fixed), (.onDemandActive, .unlimited),
             (.onDemandReady, .fixed), (.onDemandReady, .unlimited):
            return nil
        case (.exhausted, _), (.onDemandActive, .hidden), (.onDemandReady, .hidden):
            return pill
        }
    }

    private static func cardAccessibilityLabel(
        seat: SeatPresentation,
        spendRow: DashboardOnDemandSpendRow,
        showsActiveIndicator: Bool
    ) -> String {
        var parts: [String] = []
        switch seat.auth {
        case .signedOut:
            parts.append("Connect Cursor account")
        case .signingIn:
            parts.append("Signing in")
            parts.append(seat.label.text)
        case .signedIn, .needsReauth:
            parts.append(seat.label.text)
            if seat.auth == .needsReauth {
                parts.append("Needs reauth")
            }
        }
        if showsActiveIndicator {
            parts.append("Active")
        }
        if let subtitle = seat.identitySubtitle {
            parts.append(subtitle)
        }
        if let planName = seat.planName {
            parts.append(planName)
        }
        if let autoPercent = seat.autoPercent {
            parts.append(
                "\(UsagePoolLabel.cursorModels.title) \(Int(autoPercent.percent.rounded())) percent"
            )
        }
        if let apiPercent = seat.apiPercent {
            parts.append(
                "\(UsagePoolLabel.otherModels.title) \(Int(apiPercent.percent.rounded())) percent"
            )
        }
        switch spendRow {
        case .hidden:
            break
        case .fixed(let amountText, _):
            parts.append("On-demand \(amountText)")
        case .unlimited(let amountText):
            if let amountText {
                parts.append("On-demand \(amountText)")
            } else {
                parts.append("On-demand Unlimited")
            }
        }
        if let pill = dashboardStatusPill(seat.pill, spendRow: spendRow) {
            parts.append(pill.shortTitle)
        }
        if let authDetail = seat.authDetail {
            parts.append(authDetail)
        }
        return parts.joined(separator: ", ")
    }
}

extension SetHardLimitPhase {
    public func statusText(for seatID: SeatID) -> String? {
        switch self {
        case .writing(let id) where id == seatID:
            return "Saving…"
        case .writtenUnconfirmed(let id) where id == seatID:
            return "Saved; refreshing…"
        case .failed(let id, let message) where id == seatID:
            return message
        case .idle, .confirming, .writing, .succeeded, .writtenUnconfirmed, .failed:
            return nil
        }
    }

    public func disablesWrites(for seatID: SeatID) -> Bool {
        switch self {
        case .writing(let id):
            return id == seatID
        case .idle, .confirming, .succeeded, .writtenUnconfirmed, .failed:
            return false
        }
    }
}

extension Optional where Wrapped == UsagePolicy {
    /// Missing policy still allows presenting controls; adapter enforces server denial.
    fileprivate var allowsDashboardOnDemandEdit: Bool {
        switch self {
        case .none:
            return true
        case .some(let policy):
            return policy.allowsOnDemandAdjust
        }
    }
}
