import Foundation

/// Money fields from usage events. Never labels Aggregate `totalCostCents` as billed spend.
public enum ActivityCostSemantics {
    /// Parses display `usageBasedCosts` dollar strings (`"$1.23"`, `"1.23"`). `"-"`, empty → nil.
    public static func onDemandChargedCents(fromUsageBasedCosts raw: String?) -> Int64? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        if trimmed == "-" || trimmed == "—" || lowered == "none" || lowered == "n/a" {
            return nil
        }
        var digits = trimmed
        if digits.hasPrefix("$") {
            digits = String(digits.dropFirst())
        }
        digits = digits.replacingOccurrences(of: ",", with: "")
        guard let dollars = Double(digits), dollars.isFinite, dollars >= 0 else { return nil }
        return Int64((dollars * 100.0).rounded())
    }

    /// Computed usage value from `chargedCents` / `tokenUsage.totalCents` (fractional cents → whole cents).
    public static func usageValueCents(fromChargedCents value: Double?) -> Int64? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return Int64(value.rounded())
    }

    public static let onDemandChargedLabel = "On-demand charged"
    public static let usageValueLabel = "Usage value"

    public static let onDemandChargedHelp =
        "Sum of per-request on-demand charges in this range (from usage-based cost strings). Not the current billing-period on-demand total on the account card."

    public static let usageValueHelp =
        "Computed model usage value for requests in this range. Not billed on-demand spend."

    public static func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100.0
        return dollars.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// Honesty caption when money totals cover only a fetched/truncated event slice.
    public static func rangeMoneyCaption(
        money: ActivityMoneySummary,
        coverage: ActivityCoverage,
        totalRequests: Int
    ) -> String? {
        var parts: [String] = []
        if coverage.truncated {
            parts.append("Money totals cover fetched events only (truncated)")
        }
        if money.onDemandEventCount > 0, money.onDemandEventCount < totalRequests {
            parts.append(
                "On-demand charged parsed for \(money.onDemandEventCount) of \(totalRequests) requests"
            )
        }
        if money.usageValueEventCount > 0, money.usageValueEventCount < totalRequests {
            parts.append(
                "Usage value present for \(money.usageValueEventCount) of \(totalRequests) requests"
            )
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ". ") + "."
    }
}
