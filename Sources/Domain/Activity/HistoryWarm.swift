import Foundation

/// Quiet background history warm after sign-in. Memory-only; never blocks connect.
public enum HistoryWarmPhase: Sendable, Equatable {
    case idle
    case warming(completedMonths: Int, targetMonths: Int)
    case settled(warmedMonths: Int)
    case cancelled
}

public struct HistoryWarmBudget: Sendable, Equatable {
    /// Shared month cap (current + previous + older).
    public var maxMonths: Int
    /// Shared event cap across warmed months for one seat.
    public var maxEvents: Int

    public init(maxMonths: Int = 12, maxEvents: Int = 30_000) {
        self.maxMonths = maxMonths
        self.maxEvents = maxEvents
    }

    /// Background warm and interactive All Time series/token month cap.
    public static let `default` = HistoryWarmBudget()

    /// All Time Insights click. Recent months only. Does not page every month since createdAt.
    public static let interactiveAllTime = HistoryWarmBudget(maxMonths: 6, maxEvents: 8_000)
}
