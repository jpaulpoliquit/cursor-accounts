import Foundation

/// How the accounts table shows included-plan usage. On-demand stays its own column.
public enum AccountUsageMetric: String, Sendable, CaseIterable, Equatable, Hashable {
    case percent
    case tokens

    public var title: String {
        switch self {
        case .percent: "Percent"
        case .tokens: "Tokens"
        }
    }
}
