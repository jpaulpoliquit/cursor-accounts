import Charts
import CursorBarDomain
import SwiftUI

struct UsageChartPlotView: View {
    let series: UsageSeries
    let metric: UsageMetric
    let accountLabels: [SeatID: String]
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedDate: Date?
    @State private var inspectionIndex: UsageChartInspectionIndex

    init(series: UsageSeries, metric: UsageMetric, accountLabels: [SeatID: String]) {
        self.series = series
        self.metric = metric
        self.accountLabels = accountLabels
        let includeContributions: Bool = {
            if case .allAccounts = series.scope { return true }
            return false
        }()
        _inspectionIndex = State(
            initialValue: UsageChartInspectionIndex(
                points: series.points,
                accountLabels: accountLabels,
                includeContributions: includeContributions,
                metric: metric
            )
        )
    }

    var body: some View {
        Group {
            let plotted = series.plottablePoints
            if plotted.isEmpty {
                Text("No daily usage in this range.")
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            } else {
                chartStack(plotted: plotted)
            }
        }
        .onChange(of: series) { _, _ in
            rebuildInspectionIndex(clearSelection: true)
        }
        .onChange(of: accountLabels) { _, _ in
            rebuildInspectionIndex(clearSelection: true)
        }
        .onChange(of: metric) { _, _ in
            rebuildInspectionIndex(clearSelection: true)
        }
        .background(alignment: .topLeading) {
            accessibilityDayList
        }
    }

    @ViewBuilder
    private func chartStack(plotted: [UsagePoint]) -> some View {
        let yMax = plotted.map { $0.value(for: metric) }.filter(\.isFinite).max() ?? 0
        let yDomain: ClosedRange<Double> = 0...max(1, yMax)
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                totalMarks(points: plotted)
                ForEach(selectedInspections, id: \.day) { inspection in
                    selectionMarks(for: inspection)
                }
            }
            .chartLegend(.hidden)
            .chartYScale(domain: yDomain)
            .chartXSelection(value: $selectedDate)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in
                plot.background(.clear)
            }
            .frame(minHeight: 160, idealHeight: 192)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(CursorProfile.quaternaryBorder(colorScheme))
                    .frame(height: 1)
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    tooltipLayer(proxy: proxy, geo: geo)
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let anchor = proxy.plotFrame else {
                                    selectedDate = nil
                                    return
                                }
                                guard let plot = FiniteLayout.rect(geo[anchor]),
                                      plot.contains(location)
                                else {
                                    selectedDate = nil
                                    return
                                }
                                let x = location.x - plot.origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    selectedDate = date
                                }
                            case .ended:
                                selectedDate = nil
                            }
                        }
                }
            }

            axisLabels
        }
    }

    private var selectedInspection: UsageDayInspection? {
        guard let selectedDate else { return nil }
        return inspectionIndex.nearest(to: selectedDate)
    }

    private var selectedInspections: [UsageDayInspection] {
        guard let selectedInspection else { return [] }
        return [selectedInspection]
    }

    private func rebuildInspectionIndex(clearSelection: Bool) {
        let includeContributions: Bool = {
            if case .allAccounts = series.scope { return true }
            return false
        }()
        inspectionIndex = UsageChartInspectionIndex(
            points: series.points,
            accountLabels: accountLabels,
            includeContributions: includeContributions,
            metric: metric
        )
        if clearSelection {
            selectedDate = nil
        }
    }

    @ChartContentBuilder
    private func totalMarks(points: [UsagePoint]) -> some ChartContent {
        ForEach(points, id: \.day) { point in
            let x = date(for: point.day)
            let y = point.value(for: metric)
            AreaMark(
                x: .value("Day", x, unit: .day),
                y: .value(metric.chartTitle, y),
                series: .value("Series", "total")
            )
            .interpolationMethod(.linear)
            .foregroundStyle(CursorProfile.areaFill(colorScheme, highContrast: contrast == .increased))
            LineMark(
                x: .value("Day", x, unit: .day),
                y: .value(metric.chartTitle, y),
                series: .value("Series", "total")
            )
            .interpolationMethod(.linear)
            .foregroundStyle(CursorProfile.lineStroke(highContrast: contrast == .increased))
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    @ChartContentBuilder
    private func selectionMarks(for inspection: UsageDayInspection) -> some ChartContent {
        let x = date(for: inspection.day)
        let y = inspectionValue(inspection)
        // cursor.com/@jpl: 1px quaternary rule + 6pt accent dot. Nothing when not hovering.
        RuleMark(x: .value("Selected", x, unit: .day))
            .foregroundStyle(CursorProfile.quaternaryFill(colorScheme))
            .lineStyle(StrokeStyle(lineWidth: 1))
        PointMark(x: .value("Selected", x, unit: .day), y: .value(metric.chartTitle, y))
            .foregroundStyle(CursorProfile.chartAccent)
            .symbolSize(28)
    }

    private var axisLabels: some View {
        HStack {
            Text(profileDateLabel(date(for: series.rangeStart)))
            Spacer(minLength: 8)
            Text(endAxisLabel)
        }
        .font(CursorProfile.Font.axisEdge)
        .foregroundStyle(CursorProfile.tertiaryText(colorScheme))
        .accessibilityHidden(true)
    }

    private var endAxisLabel: String {
        let today = UsageDayKey.utcDay(containing: Date())
        if series.rangeStart <= today, today <= series.rangeEnd {
            return "Today"
        }
        return profileDateLabel(date(for: series.rangeEnd))
    }

    @ViewBuilder
    private func tooltipLayer(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let inspection = selectedInspection,
           let anchor = proxy.plotFrame,
           let xPos = proxy.position(forX: date(for: inspection.day)),
           let frame = FiniteLayout.rect(geo[anchor]),
           let x = FiniteLayout.dimension(xPos)
        {
            let yValue = inspectionValue(inspection)
            let rawY = proxy.position(forY: yValue)
            let fallbackY = frame.height * 0.35
            let yCandidate = (rawY?.isFinite == true ? rawY : nil) ?? fallbackY
            if let yPos = FiniteLayout.dimension(yCandidate),
               let width = FiniteLayout.dimension(tooltipWidth(inspection)),
               let cardHeight = FiniteLayout.dimension(tooltipHeight(inspection))
            {
                let stacked = showsContributionRows(inspection)
                let centerX = frame.minX + x
                let clampedX = min(max(centerX, frame.minX + width / 2 + 6), frame.maxX - width / 2 - 6)
                let pointY = frame.minY + yPos
                let above = pointY - 12 - cardHeight / 2
                let clampedY = min(max(above, frame.minY + cardHeight / 2 + 4), frame.maxY - cardHeight / 2 - 4)
                if let origin = FiniteLayout.point(x: clampedX, y: clampedY) {
                    tooltipCard(inspection)
                        .frame(width: width, alignment: stacked ? .leading : .center)
                        .position(x: origin.x, y: origin.y)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func tooltipCard(_ inspection: UsageDayInspection) -> some View {
        let stacked = showsContributionRows(inspection)
        return VStack(alignment: stacked ? .leading : .center, spacing: 0) {
            Text(inspection.tooltipTotalText(metric: metric))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .multilineTextAlignment(stacked ? .leading : .center)
            Text(profileDateLabel(date(for: inspection.day)))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CursorProfile.tertiaryText(colorScheme))
                .multilineTextAlignment(stacked ? .leading : .center)
            if metric == .costCents, inspection.costCompositionUnavailable {
                Text("Per-account cost unavailable")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CursorProfile.tertiaryText(colorScheme))
            }
            if stacked {
                ForEach(inspection.tooltipContributions(metric: metric), id: \.seatID) { row in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(CursorProfile.accountTint(for: row.seatID))
                            .frame(width: 7, height: 7)
                        Text(row.label)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(inspection.tooltipRowText(row, metric: metric))
                            .monospacedDigit()
                    }
                    .font(CursorProfile.Font.statLabel)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CursorProfile.chrome(colorScheme))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    contrast == .increased
                        ? CursorProfile.hairline(colorScheme, highContrast: true)
                        : CursorProfile.quaternaryBorder(colorScheme),
                    lineWidth: contrast == .increased ? 1.5 : 1
                )
        }
    }

    private var accessibilityDayList: some View {
        VStack(spacing: 0) {
            ForEach(inspectionIndex.inspections, id: \.day) { inspection in
                Text(inspection.day.isoDate)
                    .accessibilityLabel(inspection.accessibilityLabel(metric: metric))
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(-1)
    }

    private func inspectionValue(_ inspection: UsageDayInspection) -> Double {
        if metric == .tokens {
            return Double(inspection.totalTokens)
        }
        return Double(inspection.spendCents ?? 0)
    }

    private func showsContributionRows(_ inspection: UsageDayInspection) -> Bool {
        if case .allAccounts = series.scope, !inspection.costCompositionUnavailable {
            return !inspection.tooltipContributions(metric: metric).isEmpty
        }
        return false
    }

    private func tooltipWidth(_ inspection: UsageDayInspection) -> CGFloat {
        if showsContributionRows(inspection) {
            return 220
        }
        return 140
    }

    private func tooltipHeight(_ inspection: UsageDayInspection) -> CGFloat {
        var lines = 2
        if metric == .costCents, inspection.costCompositionUnavailable {
            lines += 1
        }
        if case .allAccounts = series.scope, !inspection.costCompositionUnavailable {
            lines += inspection.tooltipContributions(metric: metric).count
        }
        return 12 + CGFloat(lines) * 16
    }

    private func profileDateLabel(_ date: Date) -> String {
        UsageChartDateLabel.edge(date, now: Date())
    }

    private func date(for day: UsageDayKey) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day.utcMidnightMs) / 1000.0)
    }
}
