import Foundation

/// Range-aware title/copy for the token-summary Top models list.
public enum TopModelsCopy {
    public static func title(for range: UsageRange, timeZone: TimeZone = .current) -> String {
        switch range {
        case .month(let month):
            return "Top models · \(month.localizedTitle(timeZone: timeZone))"
        case .allTime:
            return "Top models · available history"
        }
    }

    public static func accessibilityHint(for range: UsageRange) -> String {
        switch range {
        case .month:
            return "Models ranked for the selected month only"
        case .allTime:
            return "Models ranked from available history, not proven entire account lifetime"
        }
    }
}
