import Foundation

/// First priced month → last priced month. The Rate column already shows the blend.
public struct ModelRateChange: Sendable, Equatable {
    public enum Direction: String, Sendable, Equatable {
        case down
        case up
        case flat
    }

    public let startCentsPerMillion: Int64
    public let endCentsPerMillion: Int64
    public let monthRangeLabel: String
    public let startMonthLabel: String
    public let endMonthLabel: String

    public init(
        startCentsPerMillion: Int64,
        endCentsPerMillion: Int64,
        monthRangeLabel: String,
        startMonthLabel: String,
        endMonthLabel: String
    ) {
        self.startCentsPerMillion = startCentsPerMillion
        self.endCentsPerMillion = endCentsPerMillion
        self.monthRangeLabel = monthRangeLabel
        self.startMonthLabel = startMonthLabel
        self.endMonthLabel = endMonthLabel
    }

    public var direction: Direction {
        if endCentsPerMillion < startCentsPerMillion { return .down }
        if endCentsPerMillion > startCentsPerMillion { return .up }
        return .flat
    }

    /// Rounded absolute percent vs the first priced month. Nil when flat or the start is zero.
    public var percent: Int? {
        guard startCentsPerMillion > 0, direction != .flat else { return nil }
        let delta = abs(endCentsPerMillion - startCentsPerMillion)
        return Int((Double(delta) * 100.0 / Double(startCentsPerMillion)).rounded())
    }

    public var startRateLabel: String {
        ActivityCostSemantics.formatCents(startCentsPerMillion)
    }

    public var endRateLabel: String {
        ActivityCostSemantics.formatCents(endCentsPerMillion)
    }

    public var accessibilityLabel: String {
        switch direction {
        case .flat:
            return "Rate unchanged at \(endRateLabel) per million tokens, \(monthRangeLabel)"
        case .down:
            if let percent {
                return "Rate down \(percent) percent, \(startRateLabel) to \(endRateLabel) per million tokens, \(monthRangeLabel)"
            }
            return "Rate down, \(startRateLabel) to \(endRateLabel) per million tokens, \(monthRangeLabel)"
        case .up:
            if let percent {
                return "Rate up \(percent) percent, \(startRateLabel) to \(endRateLabel) per million tokens, \(monthRangeLabel)"
            }
            return "Rate up, \(startRateLabel) to \(endRateLabel) per million tokens, \(monthRangeLabel)"
        }
    }
}
