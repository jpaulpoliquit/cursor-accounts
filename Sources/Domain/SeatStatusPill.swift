import Foundation

/// Attention pill for a seat. Derived only through `derive`; never stored as an independent source of truth.
public enum SeatStatusPill: String, Codable, Sendable, Equatable, Hashable {
    case exhausted
    case onDemandActive
    case onDemandReady

    public struct Input: Sendable, Equatable, Hashable {
        public enum IncludedPool: Sendable, Equatable, Hashable {
            case hasRemaining
            case exhausted
        }

        public enum OnDemandSpend: Sendable, Equatable, Hashable {
            case idle
            case consuming
        }

        public var included: IncludedPool
        public var mode: OnDemandMode
        public var spend: OnDemandSpend

        public init(included: IncludedPool, mode: OnDemandMode, spend: OnDemandSpend) {
            self.included = included
            self.mode = mode
            self.spend = spend
        }
    }

    /// Pure mapping. Priority: Active > Exhausted > Ready. Nil when off and not exhausted.
    public static func derive(_ input: Input) -> SeatStatusPill? {
        switch (input.mode, input.spend) {
        case (.fixed(_), .consuming), (.unlimited, .consuming):
            return .onDemandActive
        case (.off, _), (.fixed(_), .idle), (.unlimited, .idle):
            break
        }
        if input.included == .exhausted {
            return .exhausted
        }
        switch input.mode {
        case .off:
            return nil
        case .fixed(_), .unlimited:
            return .onDemandReady
        }
    }

    /// Exhausted from pool percentages and/or explicit display-message policy.
    /// An explicit non-exhausted server message outranks percent heuristics.
    public static func includedPool(usage: PeriodUsage, displayMessage: String?) -> Input.IncludedPool {
        if let displayMessage, displayMessageImpliesNonExhausted(displayMessage) {
            return .hasRemaining
        }
        if usage.isExhausted {
            return .exhausted
        }
        if let displayMessage, displayMessageImpliesExhausted(displayMessage) {
            return .exhausted
        }
        return .hasRemaining
    }

    public static func displayMessageImpliesExhausted(_ message: String) -> Bool {
        let lowered = message.lowercased()
        let markers = [
            "you've used all",
            "you have used all",
            "used all of your",
            "usage limit reached",
            "plan allowance exhausted",
            "included usage exhausted",
            "no usage remaining",
        ]
        return markers.contains { lowered.contains($0) }
    }

    public static func displayMessageImpliesNonExhausted(_ message: String) -> Bool {
        if displayMessageImpliesExhausted(message) { return false }
        let lowered = message.lowercased()
        let markers = [
            "usage remaining",
            "still have",
            "not exhausted",
            "allowance remaining",
        ]
        return markers.contains { lowered.contains($0) }
    }
}
