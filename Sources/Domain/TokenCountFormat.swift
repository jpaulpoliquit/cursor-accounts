import Foundation

/// Compact absolute token counts for Dashboard labels and chart axes.
public enum TokenCountFormat {
    public static func compact(_ value: Int64) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        if absValue >= 1_000_000_000 {
            let scaled = Double(absValue) / 1_000_000_000.0
            return "\(sign)\(trimmed(scaled))B"
        }
        if absValue >= 1_000_000 {
            let scaled = Double(absValue) / 1_000_000.0
            return "\(sign)\(trimmed(scaled))M"
        }
        if absValue >= 1_000 {
            let scaled = Double(absValue) / 1_000.0
            return "\(sign)\(trimmed(scaled))K"
        }
        return "\(value)"
    }

    /// Y-axis labels from plotted Doubles. Never uses currency suffixes.
    public static func axisLabel(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if abs(value) < 0.5 { return "0" }
        return compact(Int64(value.rounded()))
    }

    /// Full localized token count for accessibility.
    public static func accessibility(_ value: Int64, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale))
    }

    /// Request and account counts. Always grouped. Never raw `37388`.
    public static func grouped(_ value: Int, locale: Locale = .current) -> String {
        value.formatted(.number.grouping(.automatic).precision(.fractionLength(0)).locale(locale))
    }

    public static func grouped(_ value: Int64, locale: Locale = .current) -> String {
        value.formatted(.number.grouping(.automatic).precision(.fractionLength(0)).locale(locale))
    }

    public static func percentShare(_ share: Double) -> String {
        guard share.isFinite, share >= 0 else { return "0%" }
        if share > 0, share < 0.01 {
            return "<1%"
        }
        return "\(Int((share * 100.0).rounded()))%"
    }

    private static func trimmed(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        if abs(value.rounded() - value) < 0.05 {
            return String(format: "%.0f", value.rounded())
        }
        if value >= 10 {
            return String(format: "%.1f", value)
        }
        let one = String(format: "%.1f", value)
        if abs((value * 10).rounded() / 10 - value) < 0.05 {
            return one.replacingOccurrences(of: #"\.0$"#, with: "", options: .regularExpression)
        }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}

/// Compact currency for cost-axis chart labels. Never uses token K/M/B suffixes alone.
public enum CostCountFormat {
    public static func axisLabelCents(_ cents: Double, locale: Locale = .current) -> String {
        guard cents.isFinite else { return "$0" }
        let dollars = abs(cents) / 100.0
        let sign = cents < 0 ? "-" : ""
        if dollars >= 1_000_000_000 {
            return "\(sign)$\(trimmedCurrency(dollars / 1_000_000_000.0))B"
        }
        if dollars >= 1_000_000 {
            return "\(sign)$\(trimmedCurrency(dollars / 1_000_000.0))M"
        }
        if dollars >= 1_000 {
            return "\(sign)$\(trimmedCurrency(dollars / 1_000.0))K"
        }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = dollars < 10 ? 2 : 0
        formatter.minimumFractionDigits = 0
        let signed = cents < 0 ? -dollars : dollars
        return formatter.string(from: NSNumber(value: signed)) ?? String(format: "$%.0f", dollars)
    }

    public static func accessibilityCents(_ cents: Int32, locale: Locale = .current) -> String {
        let dollars = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: dollars)) ?? String(format: "$%.2f", dollars)
    }

    private static func trimmedCurrency(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return String(format: "%.0f", value.rounded())
        }
        return String(format: "%.1f", value)
            .replacingOccurrences(of: #"\.0$"#, with: "", options: .regularExpression)
    }
}
