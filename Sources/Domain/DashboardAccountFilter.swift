import Foundation

/// Name / email / plan substring filter for the accounts table and list.
public enum DashboardAccountFilter {
    public static func matches(_ seat: SeatPresentation, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        if seat.dashboardTitle.localizedCaseInsensitiveContains(needle) {
            return true
        }
        if let subtitle = seat.identitySubtitle, subtitle.localizedCaseInsensitiveContains(needle) {
            return true
        }
        if let plan = seat.planBadgeTitle, plan.localizedCaseInsensitiveContains(needle) {
            return true
        }
        if seat.isTeamAccount, needle.localizedCaseInsensitiveContains("team") {
            return true
        }
        return false
    }

    public static func apply(_ seats: [SeatPresentation], query: String) -> [SeatPresentation] {
        seats.filter { matches($0, query: query) }
    }

    public enum EmptyReason: Sendable, Equatable {
        case noAccountsConnected
        case noFilterMatches

        public var message: String {
            switch self {
            case .noAccountsConnected:
                return "No accounts connected"
            case .noFilterMatches:
                return "No accounts match this filter"
            }
        }
    }

    public struct Listing: Sendable, Equatable {
        public let visible: [SeatPresentation]
        public let emptyReason: EmptyReason?

        public static func make(seats: [SeatPresentation], query: String) -> Listing {
            let visible = apply(seats, query: query)
            if !visible.isEmpty {
                return Listing(visible: visible, emptyReason: nil)
            }
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !seats.isEmpty, !needle.isEmpty {
                return Listing(visible: [], emptyReason: .noFilterMatches)
            }
            return Listing(visible: [], emptyReason: .noAccountsConnected)
        }
    }
}
