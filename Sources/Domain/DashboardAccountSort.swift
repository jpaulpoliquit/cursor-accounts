import Foundation

public enum DashboardSortDirection: String, Sendable, Equatable, CaseIterable {
    case ascending
    case descending

    public var toggled: DashboardSortDirection {
        switch self {
        case .ascending:
            return .descending
        case .descending:
            return .ascending
        }
    }
}

public enum DashboardAccountLayout: String, Sendable, Equatable, Hashable, CaseIterable {
    case table
    case detail

    public var title: String {
        switch self {
        case .table:
            return "Table"
        case .detail:
            return "Detail"
        }
    }

    public var symbolName: String {
        switch self {
        case .table:
            return "tablecells"
        case .detail:
            return "list.bullet"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .table:
            return "Show accounts as a table"
        case .detail:
            return "Show accounts as a list"
        }
    }
}

public enum DashboardAccountSort: String, Sendable, Equatable, CaseIterable {
    case name
    case active
    case usage
    case onDemand
    case reset

    public var title: String {
        switch self {
        case .name:
            return "Account"
        case .active:
            return "Active"
        case .usage:
            return "Usage"
        case .onDemand:
            return "On-demand"
        case .reset:
            return "Resets"
        }
    }

    public var defaultDirection: DashboardSortDirection {
        switch self {
        case .name:
            return .ascending
        case .active, .usage, .onDemand:
            return .descending
        case .reset:
            return .ascending
        }
    }
}

public enum DashboardAccountOrdering {
    public static func sorted(
        _ seats: [SeatPresentation],
        by sort: DashboardAccountSort,
        direction: DashboardSortDirection
    ) -> [SeatPresentation] {
        seats.sorted { lhs, rhs in
            let primary = compare(lhs, rhs, by: sort)
            let result: ComparisonResult
            if primary == .orderedSame {
                result = lhs.seatID.rawValue.localizedStandardCompare(rhs.seatID.rawValue)
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
        current: DashboardAccountSort,
        direction: DashboardSortDirection,
        tapped: DashboardAccountSort
    ) -> (DashboardAccountSort, DashboardSortDirection) {
        if current == tapped {
            return (tapped, direction.toggled)
        }
        return (tapped, tapped.defaultDirection)
    }

    private static func compare(
        _ lhs: SeatPresentation,
        _ rhs: SeatPresentation,
        by sort: DashboardAccountSort
    ) -> ComparisonResult {
        switch sort {
        case .name:
            return lhs.dashboardTitle.localizedStandardCompare(rhs.dashboardTitle)
        case .active:
            return compareBool(lhs.isDesktopBound, rhs.isDesktopBound)
        case .usage:
            return compareOptionalDouble(lhs.usageSortValue, rhs.usageSortValue)
        case .onDemand:
            return compareOptionalInt64(lhs.onDemandSortValue, rhs.onDemandSortValue)
        case .reset:
            return compareOptionalDate(lhs.resetDate, rhs.resetDate)
        }
    }

    private static func compareBool(_ lhs: Bool, _ rhs: Bool) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs ? .orderedDescending : .orderedAscending
    }

    private static func compareOptionalDouble(_ lhs: Double?, _ rhs: Double?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedAscending
        case (_, nil):
            return .orderedDescending
        case let (lhs?, rhs?):
            if lhs == rhs { return .orderedSame }
            return lhs < rhs ? .orderedAscending : .orderedDescending
        }
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
            if lhs == rhs { return .orderedSame }
            return lhs < rhs ? .orderedAscending : .orderedDescending
        }
    }

    private static func compareOptionalDate(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        case let (lhs?, rhs?):
            return lhs.compare(rhs)
        }
    }
}

extension SeatPresentation {
    public var usageSortValue: Double? {
        if let totalPercent {
            return totalPercent.percent
        }
        switch (autoPercent, apiPercent) {
        case let (auto?, api?):
            return max(auto.percent, api.percent)
        case let (auto?, nil):
            return auto.percent
        case let (nil, api?):
            return api.percent
        case (nil, nil):
            return nil
        }
    }

    public var onDemandSortValue: Int64? {
        onDemand?.usedCents?.cents
    }
}
