import Foundation

/// Single formatter for on-demand spend lines. Views never convert cents.
public enum OnDemandSpendFormat {
    /// Submenu / Dashboard spend line.
    public static func line(mode: OnDemandMode, usedCents: AmountCents?) -> String {
        switch mode {
        case .off:
            if let usedCents, usedCents.cents > 0 {
                return "On-demand off · \(currency(usedCents)) used"
            }
            return "On-demand off"
        case .fixed(let limit):
            if let usedCents {
                return "\(currency(usedCents)) / $\(limit.amount)"
            }
            return "Fixed $\(limit.amount)"
        case .unlimited:
            if let usedCents {
                return "\(currency(usedCents)) · Unlimited"
            }
            return "Unlimited"
        }
    }

    public static func modeLabel(_ mode: OnDemandMode) -> String {
        switch mode {
        case .off:
            return "Off"
        case .fixed(let dollars):
            return "Fixed $\(dollars.amount)"
        case .unlimited:
            return "Unlimited"
        }
    }

    public static func currency(_ cents: AmountCents) -> String {
        String(format: "$%.2f", Double(cents.cents) / 100.0)
    }

    /// Fixed progress clamped to 1. Label still shows true used when over cap.
    public static func progressFraction(used: AmountCents, limit: PositiveDollars) -> Double {
        let limitCents = Double(limit.amount) * 100.0
        guard limitCents > 0 else { return 0 }
        return min(Double(used.cents) / limitCents, 1.0)
    }
}
