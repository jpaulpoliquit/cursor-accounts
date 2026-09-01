import CursorBarDomain
import SwiftUI

struct DashboardUsagePane: View {
    @Bindable var model: AppModel
    var dashboardVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CursorProfile.sectionSpacing) {
            if dashboardVisible {
                UsageDashboardBody(coordinator: model.usageSeries)
                usageFooter
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usageFooter: some View {
        UsageWarmFooter(coordinator: model.usageSeries)
    }
}

/// Charts and heatmap. Does not read `historyWarmPhase`, so warm ticks
/// only invalidate the footer.
private struct UsageDashboardBody: View {
    @Bindable var coordinator: UsageSeriesCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: CursorProfile.sectionSpacing) {
            if coordinator.insights != nil {
                DashboardUsageStatsRow(insights: coordinator.insights)
            }
            UsageChartView(coordinator: coordinator)
            if coordinator.series != nil || coordinator.insights != nil {
                UsageActivityHeatmapView(
                    days: ActivityHeatmapDays.merge(
                        series: coordinator.series,
                        insights: coordinator.insights
                    ),
                    range: coordinator.range,
                    timeZone: coordinator.heatmapTimeZone
                )
            }
            if let insights = coordinator.insights {
                UsageInsightsChartsView(
                    insights: insights,
                    accountLabels: coordinator.insightsAccountLabels
                )
            }
        }
    }
}

private struct UsageWarmFooter: View {
    @Bindable var coordinator: UsageSeriesCoordinator

    var body: some View {
        let caption = coordinator.insights?.coverage.caption
        let warming = {
            if case .warming = coordinator.historyWarmPhase { return true }
            return false
        }()
        if caption != nil || warming {
            HStack(alignment: .firstTextBaseline, spacing: CursorProfile.itemSpacing) {
                if let caption {
                    Text(caption)
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(caption)
                }
                Spacer(minLength: 8)
                if warming {
                    Text("Filling older history…")
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Quietly filling older history in the background")
                }
            }
        }
    }
}
