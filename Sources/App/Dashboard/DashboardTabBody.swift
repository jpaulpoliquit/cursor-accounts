import CursorBarDomain
import SwiftUI

struct DashboardTabBody: View {
    @Bindable var model: AppModel
    var dashboardVisible: Bool
    var accountsSurface: DashboardSeatSurface

    var body: some View {
        switch model.dashboardTab {
        case .accounts:
            DashboardAccountsPane(model: model, surface: accountsSurface)
        case .models:
            DashboardModelsPane(model: model, dashboardVisible: dashboardVisible)
        case .usage:
            DashboardUsagePane(model: model, dashboardVisible: dashboardVisible)
        }
    }
}
