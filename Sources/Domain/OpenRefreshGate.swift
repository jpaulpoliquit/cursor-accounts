import Foundation

/// Surface that requested a refresh-on-open. Debounced together before firing.
public enum OpenRefreshSurface: Sendable, Equatable, Hashable {
    case menuBar
    case dashboard
}

/// What to refresh after debouncing one or more open surfaces.
public struct OpenRefreshDecision: Sendable, Equatable {
    public let shouldRefreshCards: Bool
    public let shouldRefreshSeries: Bool

    public init(shouldRefreshCards: Bool, shouldRefreshSeries: Bool) {
        self.shouldRefreshCards = shouldRefreshCards
        self.shouldRefreshSeries = shouldRefreshSeries
    }
}

/// Pure open-refresh policy. Scheduling and side effects live in AppModel.
public enum OpenRefreshGate {
    public static func mergedDecision(surfaces: Set<OpenRefreshSurface>) -> OpenRefreshDecision {
        OpenRefreshDecision(
            shouldRefreshCards: !surfaces.isEmpty,
            shouldRefreshSeries: surfaces.contains(.dashboard)
        )
    }
}
