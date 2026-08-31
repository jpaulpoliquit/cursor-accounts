import Foundation

/// Newton-style Models table grouping. Trigger copy matches admin “No grouping” / “By …”.
public enum DashboardModelGroup: String, Sendable, CaseIterable, Equatable, Hashable {
    case none
    case family

    public var menuTitle: String {
        switch self {
        case .none: "No grouping"
        case .family: "Family"
        }
    }

    public var triggerLabel: String {
        switch self {
        case .none: "No grouping"
        case .family: "By family"
        }
    }
}

public enum DashboardModelSort: String, Sendable, Equatable, CaseIterable {
    case name
    case requests
    case tokens
    case value
    case charged
    case rate

    public var title: String {
        switch self {
        case .name:
            return "Model"
        case .requests:
            return "Requests"
        case .tokens:
            return "Tokens"
        case .value:
            return "Value"
        case .charged:
            return "Charged"
        case .rate:
            return "Rate"
        }
    }

    public var defaultDirection: DashboardSortDirection {
        switch self {
        case .name:
            return .ascending
        case .requests, .tokens, .value, .charged, .rate:
            return .descending
        }
    }
}

public enum DashboardModelOrdering {
    public static func sorted(
        _ rows: [ModelPricingRow],
        by sort: DashboardModelSort,
        direction: DashboardSortDirection
    ) -> [ModelPricingRow] {
        rows.sorted { lhs, rhs in
            let primary = compare(lhs, rhs, by: sort)
            let result: ComparisonResult
            if primary == .orderedSame {
                result = lhs.displayName.localizedStandardCompare(rhs.displayName)
            } else {
                result = primary
            }
            switch direction {
            case .ascending:
                return result == .orderedAscending
            case .descending:
                return result == .orderedDescending
            }
        }
    }

    public static func nextSelection(
        current: DashboardModelSort,
        direction: DashboardSortDirection,
        tapped: DashboardModelSort
    ) -> (DashboardModelSort, DashboardSortDirection) {
        if current == tapped {
            return (tapped, direction.toggled)
        }
        return (tapped, tapped.defaultDirection)
    }

    private static func compare(
        _ lhs: ModelPricingRow,
        _ rhs: ModelPricingRow,
        by sort: DashboardModelSort
    ) -> ComparisonResult {
        switch sort {
        case .name:
            return lhs.displayName.localizedStandardCompare(rhs.displayName)
        case .requests:
            return compareInt(lhs.requestCount, rhs.requestCount)
        case .tokens:
            return compareInt64(lhs.tokens, rhs.tokens)
        case .value:
            return compareInt64(lhs.usageValueCents, rhs.usageValueCents)
        case .charged:
            return compareInt64(lhs.onDemandChargedCents, rhs.onDemandChargedCents)
        case .rate:
            return compareOptionalInt64(lhs.impliedCentsPerMillion, rhs.impliedCentsPerMillion)
        }
    }

    private static func compareInt(_ lhs: Int, _ rhs: Int) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private static func compareInt64(_ lhs: Int64, _ rhs: Int64) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private static func compareOptionalInt64(_ lhs: Int64?, _ rhs: Int64?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedAscending
        case (_, nil):
            return .orderedDescending
        case let (lhs?, rhs?):
            return compareInt64(lhs, rhs)
        }
    }
}
