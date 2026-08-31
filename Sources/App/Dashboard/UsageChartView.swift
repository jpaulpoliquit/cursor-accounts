import CursorBarDomain
import SwiftUI

struct UsageChartView: View {
    @Bindable var coordinator: UsageSeriesCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                headerRow
                heroMetric
                Text(scopeCaption)
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            UsageRangeControls(coordinator: coordinator)

            chartBody
                .frame(minHeight: 192)
                .accessibilityLabel(coordinator.accessibilityDescriptor)
                .accessibilityHint(coordinator.range.utcEdgeOverlapHint ?? "")

            tokenDetails
            statusLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.gentle(reduceMotion: reduceMotion), value: coordinator.scope)
        .animation(Motion.gentle(reduceMotion: reduceMotion), value: coordinator.range)
        .animation(Motion.gentle(reduceMotion: reduceMotion), value: coordinator.resolvedMetric)
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(sectionTitle)
                .font(CursorProfile.Font.section)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            scopePicker
            if coordinator.costAvailable {
                metricPicker
            }
        }
    }

    private var sectionTitle: String {
        switch coordinator.resolvedMetric {
        case .tokens:
            switch coordinator.scope {
            case .allAccounts: "Tokens · all accounts"
            case .account: "Tokens · this account"
            }
        case .costCents: "Cost"
        }
    }

    private var scopeCaption: String {
        switch coordinator.scope {
        case .allAccounts:
            return "Graph total across every connected account."
        case .account:
            return "Graph total for the selected account only."
        }
    }

    @ViewBuilder
    private var heroMetric: some View {
        if coordinator.resolvedMetric == .costCents {
            costHero
        } else {
            tokenHero
        }
    }

    @ViewBuilder
    private var tokenHero: some View {
        if let summary = coordinator.tokenSummary {
            Text(TokenCountFormat.compact(summary.totals.total))
                .font(CursorProfile.Font.heroMetric)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityLabel(
                    "Total tokens \(TokenCountFormat.compact(summary.totals.total)), input \(TokenCountFormat.compact(summary.totals.input)), output \(TokenCountFormat.compact(summary.totals.output)), cache read \(TokenCountFormat.compact(summary.totals.cacheRead)), cache write \(TokenCountFormat.compact(summary.totals.cacheWrite))"
                )
        } else if coordinator.phase == .refreshing {
            Text("Loading token totals…")
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Loading token totals")
        }
    }

    @ViewBuilder
    private var costHero: some View {
        if let series = coordinator.series, series.costAvailable {
            let cents = series.points.reduce(0.0) { $0 + Double($1.spendCents ?? 0) }
            Text(CostCountFormat.axisLabelCents(cents))
                .font(CursorProfile.Font.heroMetric)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityLabel("Total cost \(CostCountFormat.axisLabelCents(cents))")
        } else if coordinator.phase == .refreshing {
            Text("Loading cost totals…")
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Loading cost totals")
        }
    }

    @ViewBuilder
    private var tokenDetails: some View {
        if coordinator.resolvedMetric == .tokens, let summary = coordinator.tokenSummary {
            VStack(alignment: .leading, spacing: 10) {
                if summary.totals.total > 0 {
                    bucketDetails(summary.totals)
                } else {
                    Text("No token usage in this range.")
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                }
                if !summary.topModels.isEmpty {
                    topModels(summary.topModels)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func bucketDetails(_ totals: TokenBucketCounts) -> some View {
        HStack(spacing: 12) {
            bucketChip(title: "Input", value: totals.input)
            bucketChip(title: "Output", value: totals.output)
            bucketChip(title: "Cache read", value: totals.cacheRead)
            bucketChip(title: "Cache write", value: totals.cacheWrite)
        }
        .font(CursorProfile.Font.statLabel)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityHidden(true)
    }

    private func bucketChip(title: String, value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(TokenCountFormat.compact(value))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.7))
        }
    }

    private func topModels(_ models: [RankedModelUsage]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TopModelsCopy.title(for: coordinator.range))
                .font(CursorProfile.Font.statLabel)
                .foregroundStyle(.secondary)
                .accessibilityHint(TopModelsCopy.accessibilityHint(for: coordinator.range))
            ForEach(Array(models.enumerated()), id: \.element.model.modelIntent) { _, ranked in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ranked.model.displayName)
                        .font(CursorProfile.Font.meta)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(TokenCountFormat.compact(ranked.model.buckets.total))
                        .font(CursorProfile.Font.meta.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(TokenCountFormat.percentShare(ranked.share))
                        .font(CursorProfile.Font.statLabel.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 36, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(ranked.model.displayName), \(TokenCountFormat.compact(ranked.model.buckets.total)) tokens, \(TokenCountFormat.percentShare(ranked.share))"
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(TopModelsCopy.title(for: coordinator.range))
        .accessibilityHint(TopModelsCopy.accessibilityHint(for: coordinator.range))
    }

    @ViewBuilder
    private var statusLine: some View {
        let hasContent = coordinator.series != nil || coordinator.tokenSummary != nil
        if let caption = coordinator.coverageStatusCaption {
            Text(caption)
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
        } else if coordinator.phase == .refreshing, !hasContent {
            Text("Loading usage…")
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
        } else if case .failed(let message) = coordinator.phase, !hasContent {
            Text(message)
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
        }
    }

    private var scopePicker: some View {
        Picker("Account", selection: scopeBinding) {
            ForEach(Array(coordinator.scopeOptions.enumerated()), id: \.offset) { _, option in
                Text(option.1).tag(option.0)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .tint(.secondary)
        .fixedSize()
        .accessibilityLabel("Usage scope")
    }

    private var metricPicker: some View {
        Picker("Metric", selection: metricBinding) {
            Text("Tokens").tag(UsageMetric.tokens)
            Text("Cost").tag(UsageMetric.costCents)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .tint(.secondary)
        .fixedSize()
        .accessibilityLabel("Usage metric")
    }

    private var scopeBinding: Binding<UsageScope> {
        Binding(
            get: { coordinator.scope },
            set: { coordinator.selectScope($0) }
        )
    }

    private var metricBinding: Binding<UsageMetric> {
        Binding(
            get: { coordinator.resolvedMetric },
            set: { coordinator.selectMetric($0) }
        )
    }

    @ViewBuilder
    private var chartBody: some View {
        if let series = coordinator.series, series.hasPlottablePoints {
            let labels = Dictionary(uniqueKeysWithValues: coordinator.scopeOptions.compactMap { scope, label -> (SeatID, String)? in
                guard case .account(let seatID) = scope else { return nil }
                return (seatID, label)
            })
            UsageChartPlotView(
                series: series,
                metric: coordinator.resolvedMetric,
                accountLabels: labels
            )
        } else if coordinator.series != nil {
            Text("No daily usage in this range.")
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
        } else {
            Text(coordinator.phase == .refreshing ? "Loading daily usage…" : "Connect an account to see daily tokens.")
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
        }
    }
}
