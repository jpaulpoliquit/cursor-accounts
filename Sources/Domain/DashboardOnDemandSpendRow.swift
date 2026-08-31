import Foundation

/// Dashboard spend meter after included-plan bars. Off stays hidden; Fixed/Unlimited only.
public enum DashboardOnDemandSpendRow: Sendable, Equatable, Hashable {
    case hidden
    case fixed(amountText: String, progressFraction: Double?)
    case unlimited(amountText: String?)

    public static func project(_ onDemand: OnDemandPresentation?) -> DashboardOnDemandSpendRow {
        guard let onDemand else { return .hidden }
        switch onDemand.mode {
        case .off:
            return .hidden
        case .fixed(let limit):
            let amountText: String
            if let used = onDemand.usedCents {
                amountText = "\(OnDemandSpendFormat.currency(used)) / $\(limit.amount)"
            } else {
                amountText = "Fixed $\(limit.amount)"
            }
            return .fixed(
                amountText: amountText,
                progressFraction: onDemand.fixedProgressFraction
            )
        case .unlimited:
            return .unlimited(amountText: onDemand.usedCents.map(OnDemandSpendFormat.currency))
        }
    }

    public var isVisible: Bool {
        switch self {
        case .hidden:
            return false
        case .fixed, .unlimited:
            return true
        }
    }
}

/// Checked on-demand choice inside the account-actions menu.
public enum DashboardOnDemandMenuSelection: Sendable, Equatable, Hashable {
    case off
    case fixed
    case unlimited

    public init(mode: OnDemandMode?) {
        switch mode {
        case .none, .some(.off):
            self = .off
        case .some(.fixed):
            self = .fixed
        case .some(.unlimited):
            self = .unlimited
        }
    }
}
