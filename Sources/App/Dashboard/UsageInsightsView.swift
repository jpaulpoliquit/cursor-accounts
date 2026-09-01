import CursorBarDomain
import SwiftUI

/// Work-behavior numbers under the usage graph. Shares scope/range with `UsageSeriesCoordinator`.
struct UsageInsightsView: View {
    @Bindable var coordinator: UsageSeriesCoordinator
    var includeModels: Bool = true
    var includeCharts: Bool = true
    @State private var modelSort: DashboardModelSort = .tokens
    @State private var modelSortDirection: DashboardSortDirection = DashboardModelSort.tokens.defaultDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
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

    private var header: some View {
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
        VStack(alignment: .leading, spacing: 16) {
            if includeCharts {
                UsageInsightsChartsView(
                    insights: insights,
                    accountLabels: coordinator.insightsAccountLabels
                )
            }
            stats(insights)
            if includeModels {
                UsageModelCatalogView(
                    catalog: insights.modelCatalog,
                    timeZone: TimeZone(identifier: insights.timeZoneIdentifier) ?? .current,
                    sort: $modelSort,
                    direction: $modelSortDirection
                )
            }
            if let mom = insights.monthOverMonth {
                monthComparison(mom, insights: insights)
            }
            if let caption = insights.coverage.caption {
                Text(caption)
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(caption)
            }
        }
    }

    private func stats(_ insights: ActivityInsights) -> some View {
        let money = insights.money
        let moneyHelp = [
            ActivityCostSemantics.usageValueHelp,
            ActivityCostSemantics.onDemandChargedHelp,
            ActivityCostSemantics.rangeMoneyCaption(
                money: money,
                coverage: insights.coverage,
                totalRequests: insights.totalRequests
            ),
        ].compactMap { $0 }.joined(separator: " ")
        return statsRow {
            compactStat(
                label: ActivityCostSemantics.usageValueLabel,
                value: ActivityCostSemantics.formatCents(money.usageValueCents)
            )
            .help(ActivityCostSemantics.usageValueHelp)
            compactStat(
                label: ActivityCostSemantics.onDemandChargedLabel,
                value: ActivityCostSemantics.formatCents(money.onDemandChargedCents)
            )
            .help(ActivityCostSemantics.onDemandChargedHelp)
            compactStat(
                label: insights.spanLabel,
                value: insights.medianDailySpanMs.map(ActivityInsights.durationCompact) ?? "—"
            )
            .help(insights.spanHelp)
            compactStat(
                label: insights.agentTimeLabel,
                value: insights.medianEstimatedActiveMs.map(ActivityInsights.durationCompact) ?? "—"
            )
            .help(insights.agentTimeHelp)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(ActivityCostSemantics.usageValueLabel) \(ActivityCostSemantics.formatCents(money.usageValueCents)), \(ActivityCostSemantics.onDemandChargedLabel) \(ActivityCostSemantics.formatCents(money.onDemandChargedCents))"
        )
        .accessibilityHint(moneyHelp + " " + insights.spanHelp + " " + insights.agentTimeHelp)
    }

    @ViewBuilder
    private func monthComparison(_ mom: MonthOverMonthComparison, insights: ActivityInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mom.versusLabel)
                .font(CursorProfile.Font.statLabel)
                .foregroundStyle(.secondary)
            statsRow {
                comparedStat(
                    title: "Requests",
                    current: TokenCountFormat.grouped(mom.currentRequests),
                    previous: TokenCountFormat.grouped(mom.previousRequests)
                )
                comparedStat(
                    title: "Active days",
                    current: TokenCountFormat.grouped(mom.currentActiveDays),
                    previous: TokenCountFormat.grouped(mom.previousActiveDays)
                )
                if let cur = mom.currentMedianEstimatedActiveMs, let prev = mom.previousMedianEstimatedActiveMs {
                    comparedStat(
                        title: insights.agentTimeLabel,
                        current: ActivityInsights.durationCompact(cur),
                        previous: ActivityInsights.durationCompact(prev)
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(mom.versusLabel), \(mom.currentLabel) \(mom.currentRequests) requests and \(mom.currentActiveDays) active days, \(mom.previousLabel) \(mom.previousRequests) requests and \(mom.previousActiveDays) active days"
        )
    }

    private func comparedStat(title: String, current: String, previous: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            compactStat(label: title, value: current)
            Text("was \(previous)")
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
        }
    }

    private func compactStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(CursorProfile.Font.statLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private func statsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) { content() }
            VStack(alignment: .leading, spacing: 12) { content() }
        }
    }
}
