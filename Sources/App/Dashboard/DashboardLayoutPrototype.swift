import Foundation

enum DashboardLayoutPrototype: String, CaseIterable, Equatable {
    case profileColumn
    case settingsRail
    case inspector

    var switcherName: String {
        switch self {
        case .profileColumn:
            return "A — Profile column"
        case .settingsRail:
            return "B — Settings rail"
        case .inspector:
            return "C — Inspector"
        }
    }
}
