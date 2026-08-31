import Foundation

/// Positive whole-dollar amount. Zero and negatives are unrepresentable.
public struct PositiveDollars: Codable, Sendable, Equatable, Hashable {
    public let amount: Int

    public init?(_ amount: Int) {
        guard amount > 0 else { return nil }
        self.amount = amount
    }
}

/// On-demand spend policy. Invalid fixed amounts cannot be constructed publicly.
public enum OnDemandMode: Codable, Sendable, Equatable, Hashable {
    case off
    case fixed(PositiveDollars)
    case unlimited

    public static func fixed(wholeDollars: Int) -> OnDemandMode? {
        guard let dollars = PositiveDollars(wholeDollars) else { return nil }
        return .fixed(dollars)
    }
}

/// GetHardLimit wire mapping. Off is keyed by `noUsageBasedAllowed`, not a naked guess.
public enum HardLimit: Codable, Sendable, Equatable, Hashable {
    case off
    case fixed(PositiveDollars)
    case unlimited

    public enum MappingError: Error, Sendable, Equatable {
        case invalidWireState(noUsageBasedAllowed: Bool, hardLimit: Int32?)
    }

    /// Maps Connect GetHardLimit fields. Throws on invalid combinations.
    public init(noUsageBasedAllowed: Bool?, hardLimit: Int32?) throws {
        let disallowed = noUsageBasedAllowed ?? false
        if disallowed {
            self = .off
            return
        }
        guard let hardLimit else {
            throw MappingError.invalidWireState(
                noUsageBasedAllowed: disallowed,
                hardLimit: nil
            )
        }
        if hardLimit >= Int32.max {
            self = .unlimited
            return
        }
        guard let dollars = PositiveDollars(Int(hardLimit)) else {
            throw MappingError.invalidWireState(
                noUsageBasedAllowed: disallowed,
                hardLimit: hardLimit
            )
        }
        self = .fixed(dollars)
    }

    /// Maps Connect GetHardLimit fields. Returns nil when the wire combination is invalid.
    public init?(noUsageBasedAllowed: Bool, hardLimit: Int32) {
        do {
            try self.init(noUsageBasedAllowed: Optional(noUsageBasedAllowed), hardLimit: Optional(hardLimit))
        } catch {
            return nil
        }
    }

    public var onDemandMode: OnDemandMode {
        switch self {
        case .off:
            return .off
        case .unlimited:
            return .unlimited
        case .fixed(let dollars):
            return .fixed(dollars)
        }
    }

    /// Exact SetHardLimit wire fields for this mode.
    public var setHardLimitWire: (hardLimit: Int32, noUsageBasedAllowed: Bool) {
        switch self {
        case .off:
            return (0, true)
        case .fixed(let dollars):
            return (Int32(dollars.amount), false)
        case .unlimited:
            return (Int32.max, false)
        }
    }

    public init(mode: OnDemandMode) {
        switch mode {
        case .off:
            self = .off
        case .fixed(let dollars):
            self = .fixed(dollars)
        case .unlimited:
            self = .unlimited
        }
    }
}
