import CursorBarDomain
import SwiftUI

struct UsageChartView: View {
    @Bindable var coordinator: UsageSeriesCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: CursorProfile.sectionSpacing) {
            HStack(alignment: .top, spacing: CursorProfile.cardPadding) {
                VStack(alignment: .leading, spacing: CursorProfile.clusterSpacing) {
                    heroMetric
                    Text(sectionTitle)
                        .font(CursorProfile.Font.section)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    if let heroMeta {
                        Text(heroMeta)
                            .font(CursorProfile.Font.meta)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: CursorProfile.itemSpacing)
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        scopePicker
                        if coordinator.costAvailable {
                            metricPicker
                        }
                    }
                    UsageRangeControls(coordinator: coordinator, layout: .toolbar)
                }
            }

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

    private var heroMeta: String? {
        guard coordinator.resolvedMetric == .tokens else {
            return coordinator.scope == .allAccounts
                ? "Graph total across every connected account."
                : "Graph total for the selected account only."
        }
        var parts: [String] = []
        if let insights = coordinator.insights, insights.totalRequests > 0 {
            parts.append("\(TokenCountFormat.grouped(insights.totalRequests)) requests")
        }
        if let tokenDays {
            parts.append("\(TokenCountFormat.grouped(tokenDays)) days")
        }
        if parts.isEmpty {
            return coordinator.scope == .allAccounts
                ? "Graph total across every connected account."
                : "Graph total for the selected account only."
        }
        return parts.joined(separator: " · ")
    }

    private var tokenDays: Int? {
        if let series = coordinator.series {
            let count = series.points.filter(\.hasDisplayableUsage).count
            return count > 0 ? count : nil
        }
        return nil
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
            VStack(alignment: .leading, spacing: CursorProfile.cardPadding) {
                if summary.totals.total > 0 {
                    bucketDetails(summary.totals)
                } else {
                    Text("No token usage in this range.")
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                }
                if !summary.topLines.isEmpty {
                    topModels(summary.topLines)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func bucketDetails(_ totals: TokenBucketCounts) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: CursorProfile.cardPadding) {
                bucketHeaders(totals)
            }
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: CursorProfile.cardPadding
            ) {
                bucketHeaders(totals)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func bucketHeaders(_ totals: TokenBucketCounts) -> some View {
        CursorProfileStat(label: "Input", value: TokenCountFormat.compact(totals.input))
        CursorProfileStat(label: "Output", value: TokenCountFormat.compact(totals.output))
        CursorProfileStat(label: "Cache read", value: TokenCountFormat.compact(totals.cacheRead))
        CursorProfileStat(label: "Cache write", value: TokenCountFormat.compact(totals.cacheWrite))
    }

    private func topModels(_ lines: [RankedModelLine]) -> some View {
        VStack(alignment: .leading, spacing: CursorProfile.itemSpacing) {
            Text(TopModelsCopy.title(for: coordinator.range))
                .font(CursorProfile.Font.section)
                .accessibilityHint(TopModelsCopy.accessibilityHint(for: coordinator.range))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: CursorProfile.itemSpacing) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        topModelCard(line, rank: index + 1)
                    }
                }
                VStack(alignment: .leading, spacing: CursorProfile.itemSpacing) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        topModelCard(line, rank: index + 1)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(TopModelsCopy.title(for: coordinator.range))
        .accessibilityHint(TopModelsCopy.accessibilityHint(for: coordinator.range))
    }

    private func topModelCard(_ ranked: RankedModelLine, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ranked.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("\(rank)")
                    .font(CursorProfile.Font.statLabel.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("\(TokenCountFormat.compact(ranked.tokens)) · \(TokenCountFormat.percentShare(ranked.share))")
                .font(CursorProfile.Font.meta.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CursorProfile.paper(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(CursorProfile.hairline(colorScheme, highContrast: false), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(rank). \(ranked.title), \(TokenCountFormat.compact(ranked.tokens)) tokens, \(TokenCountFormat.percentShare(ranked.share))"
        )
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
