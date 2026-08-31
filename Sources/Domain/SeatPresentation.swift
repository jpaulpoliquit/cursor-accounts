import Foundation

/// On-demand presentation. Personal used cents are currency-proven; omit when absent (team/managed).
public struct OnDemandPresentation: Sendable, Equatable, Hashable {
    public let mode: OnDemandMode
    public let usedCents: AmountCents?

    public init(mode: OnDemandMode, usedCents: AmountCents? = nil) {
        self.mode = mode
        self.usedCents = usedCents
    }

    public init(_ state: OnDemandState) {
        self.init(mode: state.mode, usedCents: state.individualUsed)
    }

    /// Compact mode label for pickers / focused summary (no used amount).
    public var modeLabel: String {
        OnDemandSpendFormat.modeLabel(mode)
    }

    /// Submenu + Dashboard spend line (`$126.20 / $190`, etc.).
    public var spendLine: String {
        OnDemandSpendFormat.line(mode: mode, usedCents: usedCents)
    }

    /// Compatibility alias for spend line (submenu/Dashboard).
    public var menuTitle: String { spendLine }

    public var fixedProgressFraction: Double? {
        guard case .fixed(let limit) = mode, let usedCents else { return nil }
        return OnDemandSpendFormat.progressFraction(used: usedCents, limit: limit)
    }
}

/// Credential-free seat view model. Identity is only via `label` (never a raw email field).
public struct SeatPresentation: Sendable, Equatable, Identifiable, Hashable {
    public var id: SeatID { seatID }

    public let seatID: SeatID
    public let label: AccountLabel
    /// Present only under `revealEmail`. Impossible under mask.
    public let revealedEmail: Email?
    public let auth: SeatAuthState
    public let planName: String?
    public let planPrice: String?
    public let resetDate: Date?
    public let autoPercent: PercentUsed?
    public let apiPercent: PercentUsed?
    public let totalPercent: PercentUsed?
    public let onDemand: OnDemandPresentation?
    public let credits: CreditBalance?
    public let policy: UsagePolicy?
    public let pill: SeatStatusPill?
    public let authDetail: String?
    public let loginPhase: SeatLoginPhase
    public let isFocused: Bool
    /// True when the live Cursor process (or code.lock) is bound to this account.
    public let isDesktopBound: Bool
    public let usageLoadState: SeatUsageLoadState
    public let identityPolicy: IdentityDisplayPolicy
    /// True when roster email or display name exists (independent of mask).
    public let hasUsableIdentity: Bool

    public init(
        seatID: SeatID,
        label: AccountLabel,
        revealedEmail: Email? = nil,
        auth: SeatAuthState,
        planName: String? = nil,
        planPrice: String? = nil,
        resetDate: Date? = nil,
        autoPercent: PercentUsed? = nil,
        apiPercent: PercentUsed? = nil,
        totalPercent: PercentUsed? = nil,
        onDemand: OnDemandPresentation? = nil,
        credits: CreditBalance? = nil,
        policy: UsagePolicy? = nil,
        pill: SeatStatusPill? = nil,
        authDetail: String? = nil,
        loginPhase: SeatLoginPhase = .idle,
        isFocused: Bool = false,
        isDesktopBound: Bool = false,
        usageLoadState: SeatUsageLoadState = .unavailable,
        identityPolicy: IdentityDisplayPolicy,
        hasUsableIdentity: Bool? = nil
    ) {
        self.seatID = seatID
        self.label = label
        switch identityPolicy {
        case .maskEmail:
            self.revealedEmail = nil
        case .revealEmail:
            self.revealedEmail = revealedEmail
        }
        self.auth = auth
        self.planName = planName
        self.planPrice = planPrice
        self.resetDate = resetDate
        self.autoPercent = autoPercent
        self.apiPercent = apiPercent
        self.totalPercent = totalPercent
        self.onDemand = onDemand
        self.credits = credits
        self.policy = policy
        self.pill = pill
        self.authDetail = authDetail
        self.loginPhase = loginPhase
        self.isFocused = isFocused
        self.isDesktopBound = isDesktopBound
        self.usageLoadState = usageLoadState
        self.identityPolicy = identityPolicy
        if let hasUsableIdentity {
            self.hasUsableIdentity = hasUsableIdentity
        } else {
            switch label {
            case .email, .displayName:
                self.hasUsableIdentity = true
            case .cursorAccount:
                self.hasUsableIdentity = false
            }
        }
    }

    public var authTitle: String {
        switch auth {
        case .signedOut: "Signed out"
        case .signingIn: "Signing in"
        case .signedIn: "Signed in"
        case .needsReauth: "Needs reauth"
        }
    }

    /// Dashboard card title. No seat-slot jargon.
    public var dashboardTitle: String {
        switch auth {
        case .signedOut:
            return "Connect Cursor account"
        case .signingIn:
            return "Signing in…"
        case .signedIn, .needsReauth:
            return label.text
        }
    }

    /// Compact menu-root account name. Full name stays in Dashboard / accessibility.
    public var menuCompactLabel: String {
        DisplayNameMenuFit.rootTitle(label.text)
    }

    public var rootMenuTitle: String {
        switch auth {
        case .signedOut:
            return "Connect Cursor account"
        case .signingIn:
            return "Signing in…"
        case .signedIn, .needsReauth:
            var parts = [menuCompactLabel]
            if let autoPercent {
                parts.append("\(UsagePoolLabel.cursorModels.compactTitle) \(Int(autoPercent.percent.rounded()))%")
            }
            if let apiPercent {
                parts.append("\(UsagePoolLabel.otherModels.compactTitle) \(Int(apiPercent.percent.rounded()))%")
            }
            if let pill {
                parts.append(pill.shortTitle)
            }
            return parts.joined(separator: " · ")
        }
    }

    public var focusedSummaryLine: String? {
        guard isFocused, auth == .signedIn || auth == .needsReauth else { return nil }
        var parts = [label.text]
        if let planName {
            parts.append(planName.capitalized)
        }
        return parts.joined(separator: " · ")
    }

    public var accessibilityLabel: String {
        var parts: [String] = []
        switch auth {
        case .signedOut:
            parts.append("Connect Cursor account")
            parts.append("account \(seatID.displayIndex)")
        case .signingIn:
            parts.append("Signing in")
            parts.append(label.text)
        case .signedIn, .needsReauth:
            parts.append(label.text)
            parts.append(authTitle)
        }
        if isDesktopBound {
            parts.append("Active")
        }
        if let revealedEmail {
            parts.append(revealedEmail.value)
        }
        if let planName { parts.append(planName) }
        if let autoPercent {
            parts.append("\(UsagePoolLabel.cursorModels.title) \(Int(autoPercent.percent.rounded())) percent")
        }
        if let apiPercent {
            parts.append("\(UsagePoolLabel.otherModels.title) \(Int(apiPercent.percent.rounded())) percent")
        }
        if let onDemand {
            parts.append(onDemand.spendLine)
        }
        if let pill {
            parts.append(pill.shortTitle)
        }
        if let authDetail {
            parts.append(authDetail)
        }
        return parts.joined(separator: ", ")
    }

    /// Menu action title. Uses privacy-safe `label`, never raw email under mask.
    public var openCursorAsSeatTitle: String {
        "Switch account to \(menuCompactLabel)…"
    }
}

public struct AppPresentation: Sendable, Equatable {
    /// Connected and in-flight seats only (stable SeatID order). Views render `connectedAccounts` + `addAccount`.
    public let seats: [SeatPresentation]
    public let connectedAccounts: [SeatPresentation]
    public let addAccount: AddAccountPresentation
    public let signedInCount: Int
    public let focusedSeatID: SeatID
    public let worstAttention: MenuAttention
    public let identityPolicy: IdentityDisplayPolicy
    public let bootstrapPhase: BootstrapPhase
    public let usageRefreshPhase: UsageRefreshPhase
    public let setHardLimitPhase: SetHardLimitPhase
    public let ideSwitchPhase: IDESwitchPhase
    public let desktopBoundSeatID: SeatID?

    public init(
        seats: [SeatPresentation],
        connectedAccounts: [SeatPresentation]? = nil,
        addAccount: AddAccountPresentation? = nil,
        signedInCount: Int? = nil,
        focusedSeatID: SeatID,
        worstAttention: MenuAttention,
        identityPolicy: IdentityDisplayPolicy,
        bootstrapPhase: BootstrapPhase,
        usageRefreshPhase: UsageRefreshPhase,
        setHardLimitPhase: SetHardLimitPhase,
        ideSwitchPhase: IDESwitchPhase = .idle,
        desktopBoundSeatID: SeatID? = nil
    ) {
        self.seats = seats
        let connected = connectedAccounts ?? seats.filter(AddAccountPresentation.isConnectedAccount)
        self.connectedAccounts = connected
        self.addAccount = addAccount ?? AddAccountPresentation.project(from: seats)
        self.signedInCount = signedInCount ?? connected.count
        self.focusedSeatID = focusedSeatID
        self.worstAttention = worstAttention
        self.identityPolicy = identityPolicy
        self.bootstrapPhase = bootstrapPhase
        self.usageRefreshPhase = usageRefreshPhase
        self.setHardLimitPhase = setHardLimitPhase
        self.ideSwitchPhase = ideSwitchPhase
        self.desktopBoundSeatID = desktopBoundSeatID
    }

    public var aggregateLine: String {
        var parts = ["\(signedInCount) connected"]
        let short = worstAttention.shortTitle
        if !short.isEmpty {
            parts.append(short)
        }
        return parts.joined(separator: " · ")
    }

    public var menuBarLabel: String {
        let short = worstAttention.shortTitle
        if short.isEmpty {
            return "MC · \(signedInCount)"
        }
        return "MC · \(signedInCount) · \(short)"
    }

    public var focusedSeat: SeatPresentation? {
        connectedAccounts.first(where: { $0.seatID == focusedSeatID })
            ?? connectedAccounts.first
            ?? seats.first(where: { $0.seatID == focusedSeatID })
    }
}

extension SeatStatusPill {
    public var shortTitle: String {
        switch self {
        case .exhausted: "Exhausted"
        case .onDemandActive: "On-demand"
        case .onDemandReady: "Ready"
        }
    }

    public var explanation: String {
        switch self {
        case .exhausted:
            return "Plan allowance is exhausted"
        case .onDemandActive:
            return "On-demand spend is active"
        case .onDemandReady:
            return "On-demand is ready with no proven spend yet"
        }
    }
}
