import CursorBarDomain
import SwiftUI

/// Production dashboard body. Identity and tabs live in the window toolbar.
struct DashboardProfileColumnView: View {
    @Bindable var model: AppModel
    var dashboardVisible: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            DashboardTabBody(
                model: model,
                dashboardVisible: dashboardVisible,
                accountsSurface: .row
            )
            .padding(CursorProfile.pagePadding)
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .dashboardScrollEdge()
        .background(CursorProfile.page(colorScheme))
    }

    private var contentMaxWidth: CGFloat {
        switch model.dashboardTab {
        case .accounts, .models:
            return CursorProfile.tableMaxWidth
        case .usage:
            return CursorProfile.columnMaxWidth
        }
    }
}
