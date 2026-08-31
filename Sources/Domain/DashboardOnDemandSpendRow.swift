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

    public var editorTitle: String {
        switch self {
        case .off:
            return "Off"
        case .fixed:
            return "Fixed"
        case .unlimited:
            return "Unlimited"
        }
    }
}

/// Draft for the dashboard on-demand editor. Views never parse dollars.
public struct OnDemandEditorDraft: Sendable, Equatable {
    public var selection: DashboardOnDemandMenuSelection
    public var fixedText: String

    public init(selection: DashboardOnDemandMenuSelection, fixedText: String) {
        self.selection = selection
        self.fixedText = fixedText
    }

    public static func make(mode: OnDemandMode?, policy: UsagePolicy?) -> OnDemandEditorDraft {
        let selection = DashboardOnDemandMenuSelection(mode: mode)
        let fixedText: String
        if case .fixed(let dollars) = mode {
            fixedText = String(dollars.amount)
        } else if let recommended = policy?.recommendedLimitCents, recommended.cents >= 100 {
            fixedText = String(recommended.cents / 100)
        } else if let current = policy?.currentLimitCents, current.cents >= 100 {
            fixedText = String(current.cents / 100)
        } else {
            fixedText = ""
        }
        return OnDemandEditorDraft(selection: selection, fixedText: fixedText)
    }

    public func resolvedMode(policy: UsagePolicy?) -> Result<OnDemandMode, OnDemandAmountValidation.Rejection> {
        switch selection {
        case .off:
            return .success(.off)
        case .unlimited:
            return .success(.unlimited)
        case .fixed:
            guard let dollars = Self.parseWholeDollars(fixedText) else {
                return .failure(.notPositiveWholeDollars)
            }
            switch OnDemandAmountValidation.validate(wholeDollars: dollars, policy: policy) {
            case .success(let amount):
                return .success(.fixed(amount))
            case .failure(let rejection):
                return .failure(rejection)
            }
        }
    }

    public static func parseWholeDollars(_ raw: String) -> Int? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$") {
            trimmed.removeFirst()
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        trimmed = trimmed.replacingOccurrences(of: ",", with: "")
        return Int(trimmed)
    }
}
