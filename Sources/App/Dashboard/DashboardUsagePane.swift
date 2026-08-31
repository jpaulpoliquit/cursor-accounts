import CursorBarDomain
import SwiftUI

struct DashboardUsagePane: View {
    @Bindable var model: AppModel
    var dashboardVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CursorProfile.sectionSpacing) {
            if dashboardVisible {
                if let insights = model.usageSeries.insights {
                    DashboardUsageStatsRow(
                        insights: insights,
                        thisSeatID: model.presentation.menuBarStatusSeat?.seatID,
                        thisSeatTitle: model.presentation.menuBarStatusSeat?.dashboardTitle ?? "This account"
                    )
                }
                UsageChartView(coordinator: model.usageSeries)
                if let insights = model.usageSeries.insights {
                    UsageActivityHeatmapView(
                        days: insights.days,
                        range: insights.range,
                        timeZone: TimeZone(identifier: insights.timeZoneIdentifier) ?? .current
                    )
                    UsageInsightsChartsView(
                        insights: insights,
                        accountLabels: model.usageSeries.insightsAccountLabels
                    )
                }
                UsageInsightsView(
                    coordinator: model.usageSeries,
                    includeModels: false,
                    includeCharts: false
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
