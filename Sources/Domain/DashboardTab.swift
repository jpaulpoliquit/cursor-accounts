import Foundation

/// Dashboard surfaces. Order is Accounts → Models → Usage.
public enum DashboardTab: String, CaseIterable, Sendable, Equatable, Hashable {
    case accounts
    case models
    case usage

    public var title: String {
        switch self {
        case .accounts:
            return "Accounts"
        case .models:
            return "Models"
        case .usage:
            return "Usage"
        }
    }

    public var accessibilityLabel: String {
        "\(title) tab"
    }
}
