import CursorBarDomain
import SwiftUI

/// Production dashboard body. Title bar is chrome-only; name and tabs live in the page.
struct DashboardProfileColumnView: View {
    @Bindable var model: AppModel
    var dashboardVisible: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardPageHeader(model: model)
                .padding(.horizontal, contentPadding)
                .padding(.top, 36)
                .padding(.bottom, 16)
            ScrollView {
                DashboardTabBody(
                    model: model,
                    dashboardVisible: dashboardVisible,
                    accountsSurface: .row
                )
                .padding(.horizontal, contentPadding)
                .padding(.bottom, contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .dashboardScrollEdge()
        }
        .background(CursorProfile.page(colorScheme))
    }

    private var contentPadding: CGFloat {
        24
    }
}
