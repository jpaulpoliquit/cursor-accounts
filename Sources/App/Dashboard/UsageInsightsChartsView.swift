import Charts
import CursorBarDomain
import SwiftUI

/// 24-hour and daily activity charts with precomputed hover inspection + VoiceOver lists.
struct UsageInsightsChartsView: View {
    let insights: ActivityInsights
    let accountLabels: [SeatID: String]
    @Environment(\.colorScheme) private var colorScheme

    @State private var inspectionIndex: ActivityInspectionIndex
    @State private var selectedHour: Double?
    @State private var selectedPeriodLabel: String?

    init(insights: ActivityInsights, accountLabels: [SeatID: String] = [:]) {
        self.insights = insights
        self.accountLabels = accountLabels
        _inspectionIndex = State(
            initialValue: ActivityInspectionIndex(
                insights: insights,
                accountLabels: accountLabels
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CursorProfile.sectionSpacing) {
            whenYouWork
            if showsPeriodChart {
                dailyActivity
            }
        }
        .onChange(of: insights) { _, _ in
            rebuildInspectionIndex(clearSelection: true)
        }
        .onChange(of: accountLabels) { _, _ in
            rebuildInspectionIndex(clearSelection: true)
        }
    }

    private func rebuildInspectionIndex(clearSelection: Bool) {
        inspectionIndex = ActivityInspectionIndex(
            insights: insights,
            accountLabels: accountLabels
        )
        if clearSelection {
            selectedHour = nil
            selectedPeriodLabel = nil
        }
    }

    private var timeZone: TimeZone {
        TimeZone(identifier: insights.timeZoneIdentifier) ?? .current
    }

    /// All Time already has the year heatmap. Monthly bars only reflect fetched events (May–Sep).
    private var showsPeriodChart: Bool {
        if case .allTime = insights.range { return false }
        return true
    }

    private var whenYouWork: some View {
        VStack(alignment: .leading, spacing: CursorProfile.itemSpacing) {
            Text("When you work")
                .font(CursorProfile.Font.section)
            if insights.hourOfDayCounts.allSatisfy({ $0 == 0 }) {
                Text("No request activity in this range.")
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
            } else {
                Chart(Array(insights.hourOfDayCounts.enumerated()), id: \.offset) { item in
                    BarMark(
                        x: .value("Hour", item.offset),
                        y: .value("Requests", item.element),
                        width: .ratio(0.68)
                    )
                    .foregroundStyle(CursorProfile.chartAccent)
                    .cornerRadius(2)
                    if let hour = selectedHourInspection {
                        RuleMark(x: .value("Selected", hour.hour))
                            .foregroundStyle(Color.secondary.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXScale(domain: -0.5...23.5)
                .chartYScale(domain: 0...max(1, insights.hourOfDayCounts.max() ?? 0))
                .chartXSelection(value: $selectedHour)
                .onContinuousHover { phase in
                    if case .ended = phase {
                        selectedHour = nil
                    }
                }
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18]) { value in
                        AxisValueLabel {
                            if let hour = value.as(Int.self) {
                                Text(ActivityInsights.clockLabel(hour))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .chartPlotStyle { plot in
                    plot.padding(.bottom, 2)
                }
                .frame(height: 128)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        hourTooltip(proxy: proxy, geo: geo)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(insights.peakHourRangeAccessibility)
                .background(alignment: .topLeading) { hourAccessibilityList }
            }
        }
    }

    private var dailyActivity: some View {
        let points = ActivityChartAggregation.points(from: insights)
        let usesMonths = inspectionIndex.usesMonthBuckets
        return VStack(alignment: .leading, spacing: CursorProfile.itemSpacing) {
            Text(usesMonths ? "Activity by month" : "Daily activity")
                .font(CursorProfile.Font.section)
            if points.isEmpty {
                Text("No active days in this range.")
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Period", point.label),
                        y: .value("Requests", point.requestCount)
                    )
                    .foregroundStyle(CursorProfile.chartAccent)
                    if let selected = selectedPeriodInspection, selected.label == point.label {
                        RuleMark(x: .value("Selected", point.label))
                            .foregroundStyle(Color.secondary.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXSelection(value: $selectedPeriodLabel)
                .onContinuousHover { phase in
                    if case .ended = phase {
                        selectedPeriodLabel = nil
                    }
                }
                .chartYScale(domain: 0...max(1, points.map(\.requestCount).max() ?? 0))
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartYAxis(.hidden)
                .chartPlotStyle { plot in
                    plot.padding(.horizontal, 12)
                }
                .frame(height: 100)
                .padding(.trailing, 4)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        periodTooltip(proxy: proxy, geo: geo)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(usesMonths ? "Monthly" : "Daily") activity, \(insights.activeDayCount) active days, \(insights.totalRequests) requests"
                )
                .background(alignment: .topLeading) { periodAccessibilityList }
            }
        }
    }

    private var selectedHourInspection: ActivityHourInspection? {
        guard let selectedHour else { return nil }
        return inspectionIndex.hour(nearest: selectedHour)
    }

    private var selectedPeriodInspection: ActivityPeriodInspection? {
        inspectionIndex.period(nearestLabel: selectedPeriodLabel)
    }

    @ViewBuilder
    private func hourTooltip(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let inspection = selectedHourInspection,
           let anchor = proxy.plotFrame,
           let xPos = proxy.position(forX: inspection.hour),
           let frame = FiniteLayout.rect(geo[anchor])
        {
            clampedTooltip(lines: inspection.tooltipLines, xPos: xPos, frame: frame, width: 168)
        }
    }

    @ViewBuilder
    private func periodTooltip(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let inspection = selectedPeriodInspection,
           let anchor = proxy.plotFrame,
           let xPos = proxy.position(forX: inspection.label),
           let frame = FiniteLayout.rect(geo[anchor])
        {
            clampedTooltip(
                lines: inspection.tooltipLines(timeZone: timeZone, idleGap: insights.idleGap),
                xPos: xPos,
                frame: frame,
                width: 240
            )
        }
    }

    @ViewBuilder
    private func clampedTooltip(
        lines: [String],
        xPos: CGFloat,
        frame: CGRect,
        width: CGFloat
    ) -> some View {
        if let x = FiniteLayout.dimension(xPos),
           let width = FiniteLayout.dimension(width),
           let originY = FiniteLayout.dimension(frame.minY + 52)
        {
            let centerX = frame.minX + x
            let clampedX = min(
                max(centerX, frame.minX + width / 2 + 8),
                frame.maxX - width / 2 - 8
            )
            if let originX = FiniteLayout.dimension(clampedX) {
                VStack(alignment: .center, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: index == 0 ? 12 : 11, weight: index == 0 ? .semibold : .medium))
                            .foregroundStyle(index == 0 ? .primary : CursorProfile.tertiaryText(colorScheme))
                            .monospacedDigit()
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CursorProfile.chrome(colorScheme))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(CursorProfile.quaternaryBorder(colorScheme), lineWidth: 1)
                }
                .position(x: originX, y: originY)
                .allowsHitTesting(false)
            }
        }
    }

    private var hourAccessibilityList: some View {
        VStack(spacing: 0) {
            ForEach(inspectionIndex.hours, id: \.hour) { hour in
                Text(ActivityInsights.clockLabel(hour.hour))
                    .accessibilityLabel(hour.accessibilityLabel)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(-1)
    }

    private var periodAccessibilityList: some View {
        VStack(spacing: 0) {
            ForEach(Array(inspectionIndex.periods.enumerated()), id: \.offset) { _, period in
                Text(period.label)
                    .accessibilityLabel(period.accessibilityLabel(timeZone: timeZone))
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(-1)
    }
}
