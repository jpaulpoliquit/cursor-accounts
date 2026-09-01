import Foundation

/// Credential-free root-menu account row. Metrics are percent-used, matching Dashboard wire.
public struct AccountMenuRowModel: Sendable, Equatable, Hashable {
    public let primaryName: String
    public let helpText: String
    public let secondarySummary: String
    /// Single high-contrast submenu status line. No identity repeat, no hover tooltip copy.
    public let submenuStatusLine: String
    public let cursorUsedPercent: Int?
    public let otherUsedPercent: Int?
    public let pill: SeatStatusPill?
    /// True only when the shared Cursor session identity matches this seat.
    public let showsActiveIDE: Bool
    public let accessibilityLabel: String

    public init(
        primaryName: String,
        helpText: String,
        secondarySummary: String,
        submenuStatusLine: String,
        cursorUsedPercent: Int?,
        otherUsedPercent: Int?,
        pill: SeatStatusPill?,
        showsActiveIDE: Bool,
        accessibilityLabel: String
    ) {
        self.primaryName = primaryName
        self.helpText = helpText
        self.secondarySummary = secondarySummary
        self.submenuStatusLine = submenuStatusLine
        self.cursorUsedPercent = cursorUsedPercent
        self.otherUsedPercent = otherUsedPercent
        self.pill = pill
        self.showsActiveIDE = showsActiveIDE
        self.accessibilityLabel = accessibilityLabel
    }

    public init(
        seat: SeatPresentation,
        menuPrimary: AccountLabel,
        aliasLabel: AccountLabel,
        usageLoadState: SeatUsageLoadState
    ) {
        let rawPrimary = seat.userLabel?.value ?? menuPrimary.text
        let fittedPrimary = DisplayNameMenuFit.rootTitle(rawPrimary)
        self.primaryName = fittedPrimary
        self.helpText = AccountLabelResolver.menuHelpText(
            policy: seat.identityPolicy,
            menuPrimary: menuPrimary,
            aliasLabel: aliasLabel
        )
        self.cursorUsedPercent = seat.autoPercent.map { Int($0.percent.rounded()) }
        self.otherUsedPercent = seat.apiPercent.map { Int($0.percent.rounded()) }
        self.pill = seat.pill
        self.showsActiveIDE = seat.isDesktopBound
        self.secondarySummary = Self.secondarySummary(for: seat, usageLoadState: usageLoadState)
        self.submenuStatusLine = Self.submenuStatusLine(for: seat, usageLoadState: usageLoadState)
        self.accessibilityLabel = seat.accessibilityLabel
    }

    /// NSMenu flattens custom labels to this string. Checkmark must live in the title.
    public var rootItemTitle: String {
        showsActiveIDE ? "✓ \(primaryName)" : primaryName
    }

    public var cursorMetricText: String {
        Self.metricText(pool: .cursorModels, percent: cursorUsedPercent, loadState: nil)
    }

    public var otherMetricText: String {
        Self.metricText(pool: .otherModels, percent: otherUsedPercent, loadState: nil)
    }

    /// Stable secondary line. Missing pools keep a reserved placeholder so columns compare.
    public var metricsLine: String {
        "\(cursorMetricText)  \(otherMetricText)"
    }

    public static func metricText(
        pool: UsagePoolLabel,
        percent: Int?,
        loadState: SeatUsageLoadState? = nil
    ) -> String {
        let value: String
        if let loadState, loadState != .ready {
            switch loadState {
            case .pending:
                value = "  …"
            case .failed:
                value = " err"
            case .unavailable, .ready:
                value = "  —"
            }
        } else if let percent {
            value = String(format: "%3d%%", percent)
        } else {
            value = "  —"
        }
        return "\(pool.compactTitle) \(value)"
    }

    public static func secondarySummary(
        for seat: SeatPresentation,
        usageLoadState: SeatUsageLoadState? = nil
    ) -> String {
        var parts: [String] = []
        if let planName = seat.planName {
            parts.append(planName.capitalized)
        }
        let load = usageLoadState ?? seat.usageLoadState
        let metricsLoad: SeatUsageLoadState? = {
            switch load {
            case .ready:
                return nil
            case .unavailable:
                if seat.autoPercent != nil || seat.apiPercent != nil {
                    return nil
                }
                return .pending
            case .pending, .failed:
                return load
            }
        }()
        parts.append(
            metricText(
                pool: .cursorModels,
                percent: seat.autoPercent.map { Int($0.percent.rounded()) },
                loadState: metricsLoad
            )
        )
        parts.append(
            metricText(
                pool: .otherModels,
                percent: seat.apiPercent.map { Int($0.percent.rounded()) },
                loadState: metricsLoad
            )
        )
        if let pill = seat.pill {
            parts.append(pill.shortTitle)
        }
        return parts.joined(separator: " · ")
    }

    public static func secondarySummary(for seat: SeatPresentation) -> String {
        secondarySummary(for: seat, usageLoadState: nil)
    }

    /// Submenu facts only. Identity stays on the parent item; skip "Signed in" and pill essays.
    public static func submenuStatusLine(
        for seat: SeatPresentation,
        usageLoadState: SeatUsageLoadState? = nil
    ) -> String {
        var parts: [String] = []
        if seat.isDesktopBound {
            parts.append("Active")
        }
        switch seat.auth {
        case .signedOut:
            parts.append("Signed out")
        case .signingIn:
            parts.append("Signing in")
        case .needsReauth:
            parts.append("Needs reauth")
        case .signedIn:
            break
        }
        if let planName = seat.planName {
            parts.append(planName.capitalized)
        }
        let load = usageLoadState ?? seat.usageLoadState
        let metricsLoad: SeatUsageLoadState? = {
            switch load {
            case .ready:
                return nil
            case .unavailable:
                if seat.autoPercent != nil || seat.apiPercent != nil {
                    return nil
                }
                return .pending
            case .pending, .failed:
                return load
            }
        }()
        parts.append(
            metricText(
                pool: .cursorModels,
                percent: seat.autoPercent.map { Int($0.percent.rounded()) },
                loadState: metricsLoad
            )
        )
        parts.append(
            metricText(
                pool: .otherModels,
                percent: seat.apiPercent.map { Int($0.percent.rounded()) },
                loadState: metricsLoad
            )
        )
        if let onDemand = seat.onDemand {
            parts.append(onDemand.spendLine)
        } else if let pill = seat.pill {
            parts.append(pill.shortTitle)
        }
        if let credits = seat.credits, case .present(let balance, _, _) = credits {
            parts.append("Credits $\(String(format: "%.2f", Double(balance.cents) / 100.0))")
        }
        return parts.joined(separator: " · ")
    }
}

extension SeatPresentation {
    public var menuRow: AccountMenuRowModel {
        let source = AccountLabelResolver.Source(
            seatID: seatID,
            email: revealedEmail ?? inferredEmailForMenuPrimary,
            displayName: inferredDisplayNameForMenuPrimary
        )
        let menuPrimary = AccountLabelResolver.menuPrimary(policy: identityPolicy, source: source)
        let aliasLabel = label
        return AccountMenuRowModel(
            seat: self,
            menuPrimary: menuPrimary,
            aliasLabel: aliasLabel,
            usageLoadState: usageLoadState
        )
    }

    /// Reveal path uses `revealedEmail`; mask path never exposes email to menu primary resolver.
    private var inferredEmailForMenuPrimary: Email? {
        switch identityPolicy {
        case .maskEmail:
            return nil
        case .revealEmail:
            return revealedEmail
        }
    }

    private var inferredDisplayNameForMenuPrimary: DisplayName? {
        if case .displayName(let name) = label {
            return name
        }
        return nil
    }
}
