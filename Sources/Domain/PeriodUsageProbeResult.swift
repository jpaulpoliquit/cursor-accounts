import Foundation

/// Minimal typed period result from DashboardService/GetCurrentPeriodUsage.
public struct PeriodUsageProbeResult: Sendable, Equatable, Hashable {
    public let usage: PeriodUsage
    public let displayMessage: String?

    public init(usage: PeriodUsage, displayMessage: String? = nil) {
        self.usage = usage
        self.displayMessage = displayMessage
    }
}

public enum SessionProbeFailure: Error, Sendable, Equatable {
    case httpStatus(Int)
    case transport
    case decode
    case cancelled

    public var surfaceMessage: String {
        switch self {
        case .httpStatus(let code):
            "Usage probe failed (HTTP \(code))"
        case .transport:
            "Usage probe failed (network)"
        case .decode:
            "Usage probe failed (unexpected response)"
        case .cancelled:
            "Usage probe cancelled"
        }
    }
}

extension SessionProbeFailure: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { surfaceMessage }
    public var debugDescription: String { surfaceMessage }
}
