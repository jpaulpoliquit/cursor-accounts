import CursorBarDomain
import SwiftUI

struct DashboardUsagePane: View {
    @Bindable var model: AppModel
    var dashboardVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CursorProfile.sectionSpacing) {
            if dashboardVisible {
                if let insights = model.usageSeries.insights {
                    DashboardUsageStatsRow(insights: insights)
                }
                UsageChartView(coordinator: model.usageSeries)
                UsageInsightsView(coordinator: model.usageSeries, includeModels: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
