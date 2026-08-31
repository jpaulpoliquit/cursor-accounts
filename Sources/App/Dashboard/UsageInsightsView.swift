import CursorBarDomain
import SwiftUI

/// Calm work-behavior insights under the usage graph. Shares scope/range with `UsageSeriesCoordinator`.
struct UsageInsightsView: View {
    @Bindable var coordinator: UsageSeriesCoordinator
    var includeModels: Bool = true
    var includeCharts: Bool = true
    @State private var modelSort: DashboardModelSort = .tokens
    @State private var modelSortDirection: DashboardSortDirection = DashboardModelSort.tokens.defaultDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: CursorProfile.sectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("Insights")
                    .font(CursorProfile.Font.section)
                Spacer(minLength: 8)
                if case .warming = coordinator.historyWarmPhase {
                    Text("Filling older history…")
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Quietly filling older history in the background")
                }
            }

            if let insights = coordinator.insights {
                content(insights)
            } else {
                Text(emptyCopy)
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(coordinator.insightsAccessibilityDescriptor)
        .animation(Motion.gentle(reduceMotion: reduceMotion), value: coordinator.insights?.totalRequests)
    }

    private var emptyCopy: String {
        switch coordinator.insightsPhase {
        case .refreshing:
            return "Loading insights…"
        case .idle:
            return "Connect an account to see work insights."
        case .failed(let message):
            return message
        case .settled:
            return "No request activity in this range."
        }
    }

    private func content(_ insights: ActivityInsights) -> some View {
        VStack(alignment: .leading, spacing: CursorProfile.sectionSpacing) {
            if includeCharts {
                UsageInsightsChartsView(
                    insights: insights,
                    accountLabels: coordinator.insightsAccountLabels
                )
            }
            moneySummary(insights)
            if includeModels {
                UsageModelCatalogView(
                    catalog: insights.modelCatalog,
                    timeZone: TimeZone(identifier: insights.timeZoneIdentifier) ?? .current,
                    sort: $modelSort,
                    direction: $modelSortDirection
                )
            }
            timeSummary(insights)
            if let mom = insights.monthOverMonth {
                monthComparison(mom)
            }
            if let caption = insights.coverage.caption {
                Text(caption)
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(caption)
            }
        }
    }

    private func moneySummary(_ insights: ActivityInsights) -> some View {
        let money = insights.money
        return VStack(alignment: .leading, spacing: 10) {
            Text("Range money")
                .font(CursorProfile.Font.section)
            statsRow {
                CursorProfileStat(
                    label: ActivityCostSemantics.usageValueLabel,
                    value: ActivityCostSemantics.formatCents(money.usageValueCents)
                )
                .help(ActivityCostSemantics.usageValueHelp)
                CursorProfileStat(
                    label: ActivityCostSemantics.onDemandChargedLabel,
                    value: ActivityCostSemantics.formatCents(money.onDemandChargedCents)
                )
                .help(ActivityCostSemantics.onDemandChargedHelp)
            }
            Text("These are separate totals for the selected range. They are not added together, and they are not the current-period on-demand total on the account card.")
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let caption = ActivityCostSemantics.rangeMoneyCaption(
                money: money,
                coverage: insights.coverage,
                totalRequests: insights.totalRequests
            ) {
                Text(caption)
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(ActivityCostSemantics.usageValueLabel) \(ActivityCostSemantics.formatCents(money.usageValueCents)), \(ActivityCostSemantics.onDemandChargedLabel) \(ActivityCostSemantics.formatCents(money.onDemandChargedCents))"
        )
        .accessibilityHint(
            "\(ActivityCostSemantics.usageValueHelp) \(ActivityCostSemantics.onDemandChargedHelp)"
        )
    }

    private func timeSummary(_ insights: ActivityInsights) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time summary")
                .font(CursorProfile.Font.section)
            statsRow {
                CursorProfileStat(label: "Active days", value: "\(insights.activeDayCount)")
                CursorProfileStat(
                    label: "Median daily span",
                    value: insights.medianDailySpanMs.map(ActivityInsights.durationCompact) ?? "—"
                )
                CursorProfileStat(
                    label: "Est. agent-active",
                    value: insights.medianEstimatedActiveMs.map(ActivityInsights.durationCompact) ?? "—"
                )
            }
            Text("Daily span is first to last request. Estimated agent-active time. \(insights.idleGap.methodologyCopy)")
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if insights.estimatedActiveIsPerSeatSum {
                Text("Across accounts, estimated agent-active time is summed per account.")
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(timeSummaryAccessibility(insights))
    }

    private func timeSummaryAccessibility(_ insights: ActivityInsights) -> String {
        var parts = ["Time summary", "\(insights.activeDayCount) active days"]
        if let span = insights.medianDailySpanMs {
            parts.append("median daily span \(ActivityInsights.durationAccessibility(span))")
        }
        if let active = insights.medianEstimatedActiveMs {
            parts.append("median estimated agent-active time \(ActivityInsights.durationAccessibility(active))")
        }
        parts.append(insights.idleGap.accessibilityLabel)
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func monthComparison(_ mom: MonthOverMonthComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Month comparison")
                .font(CursorProfile.Font.section)
            if mom.currentIsPartial {
                Text("\(mom.currentLabel) versus \(mom.previousLabel)")
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
            }
            statsRow {
                comparedStat(
                    title: "Requests",
                    current: "\(mom.currentRequests)",
                    previous: "\(mom.previousRequests)"
                )
                comparedStat(
                    title: "Active days",
                    current: "\(mom.currentActiveDays)",
                    previous: "\(mom.previousActiveDays)"
                )
                if let cur = mom.currentMedianEstimatedActiveMs, let prev = mom.previousMedianEstimatedActiveMs {
                    comparedStat(
                        title: "Est. active",
                        current: ActivityInsights.durationCompact(cur),
                        previous: ActivityInsights.durationCompact(prev)
                    )
                }
            }
            if mom.allowsProse {
                ForEach(mom.proseLines, id: \.self) { line in
                    Text(line)
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Month comparison, \(mom.currentLabel) \(mom.currentRequests) requests and \(mom.currentActiveDays) active days, \(mom.previousLabel) \(mom.previousRequests) requests and \(mom.previousActiveDays) active days"
        )
    }

    private func comparedStat(title: String, current: String, previous: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            CursorProfileStat(label: title, value: current)
            Text("was \(previous)")
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
        }
    }

    private func statsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) { content() }
            VStack(alignment: .leading, spacing: 12) { content() }
        }
    }
}
