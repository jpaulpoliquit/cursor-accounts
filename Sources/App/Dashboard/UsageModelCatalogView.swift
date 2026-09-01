import CursorBarDomain
import SwiftUI

/// Full model list from Insights history, with implied Cursor rates and subsidy.
struct UsageModelCatalogView: View {
    let catalog: ModelPricingCatalog
    let timeZone: TimeZone
    var showsTitle: Bool = true
    var group: DashboardModelGroup = .family
    @Binding var sort: DashboardModelSort
    @Binding var direction: DashboardSortDirection
    @Environment(\.colorScheme) private var colorScheme
    @State private var collapsedFamilies: Set<ModelDisplayNames.Family> = []
    @State private var collapsedLines: Set<String> = []
    @State private var hoveredIntent: String?

    init(
        catalog: ModelPricingCatalog,
        timeZone: TimeZone,
        showsTitle: Bool = true,
        group: DashboardModelGroup = .family,
        sort: Binding<DashboardModelSort>,
        direction: Binding<DashboardSortDirection>
    ) {
        self.catalog = catalog
        self.timeZone = timeZone
        self.showsTitle = showsTitle
        self.group = group
        _sort = sort
        _direction = direction
    }

    var body: some View {
        if catalog.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: CursorProfile.sectionSpacing) {
                if showsTitle {
                    Text("Models")
                        .font(CursorProfile.Font.section)
                }
                totals
                VStack(alignment: .leading, spacing: CursorProfile.cardPadding) {
                    table
                    Text(ModelPricingCatalog.methodologyCopy)
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "Models, \(catalog.models.count) models, usage value \(ActivityCostSemantics.formatCents(catalog.totalUsageValueCents)), subsidized \(ActivityCostSemantics.formatCents(catalog.totalSubsidizedCents))"
            )
        }
    }

    private var rows: [ModelPricingRow] {
        DashboardModelOrdering.sorted(catalog.models, by: sort, direction: direction)
    }

    private var familySections: [ModelFamilySection] {
        ActivityModelCatalog.sectionsByFamily(catalog.models).map { section in
            ModelFamilySection(
                family: section.family,
                rows: DashboardModelOrdering.sorted(section.rows, by: sort, direction: direction)
            )
        }
    }

    private var totals: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: CursorProfile.sectionSpacing) {
                totalStats
            }
            VStack(alignment: .leading, spacing: CursorProfile.cardPadding) {
                totalStats
            }
        }
    }

    @ViewBuilder
    private var totalStats: some View {
        headerStat(
            label: ActivityCostSemantics.usageValueLabel,
            value: ActivityCostSemantics.formatCents(catalog.totalUsageValueCents)
        )
        headerStat(
            label: ActivityCostSemantics.onDemandChargedLabel,
            value: ActivityCostSemantics.formatCents(catalog.totalOnDemandChargedCents)
        )
        headerStat(
            label: "Subsidized",
            value: ActivityCostSemantics.formatCents(catalog.totalSubsidizedCents)
        )
        .help(ModelPricingCatalog.subsidizedHelp)
    }

    private func headerStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: CursorProfile.clusterSpacing) {
            Text(value)
                .font(CursorProfile.Font.statValue)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(CursorProfile.Font.section)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            if group == .family {
                ForEach(familySections) { section in
                    familyGroup(section)
                }
            } else {
                columnHeader(nested: false)
                ForEach(rows, id: \.modelIntent) { row in
                    modelRow(row, nameInset: 0)
                }
            }
        }
        .background(CursorProfile.paper(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CursorProfile.hairline(colorScheme, highContrast: false), lineWidth: 1)
        }
    }

    private func familyGroup(_ section: ModelFamilySection) -> some View {
        let collapsed = collapsedFamilies.contains(section.family)
        let lines = ActivityModelCatalog.lines(in: section.rows, family: section.family)
        let showLines = lines.count > 1
        return VStack(alignment: .leading, spacing: 0) {
            DashboardTableGroupHeader(
                title: section.family.title,
                countLabel: ModelDisplayNames.familyGroupCountLabel(section.rows.count),
                kind: .family,
                collapsed: collapsed
            ) {
                toggleFamily(section.family)
            }
            if !collapsed {
                columnHeader(nested: true)
                if showLines {
                    ForEach(lines) { line in
                        lineGroup(line, family: section.family)
                    }
                } else {
                    ForEach(section.rows, id: \.modelIntent) { row in
                        modelRow(row, nameInset: DashboardTableGroupMetrics.nestedInset)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func lineGroup(_ section: ModelLineSection, family: ModelDisplayNames.Family) -> some View {
        let key = lineKey(family, section.line)
        let collapsed = collapsedLines.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            DashboardTableGroupHeader(
                title: section.line.title,
                countLabel: ModelDisplayNames.familyGroupCountLabel(section.rows.count),
                kind: .line,
                collapsed: collapsed
            ) {
                toggleLine(key)
            }
            if !collapsed {
                ForEach(section.rows, id: \.modelIntent) { row in
                    modelRow(row, nameInset: DashboardTableGroupMetrics.nestedInset * 2)
                }
            }
        }
    }

    private func toggleFamily(_ family: ModelDisplayNames.Family) {
        if collapsedFamilies.contains(family) {
            collapsedFamilies.remove(family)
        } else {
            collapsedFamilies.insert(family)
        }
    }

    private func toggleLine(_ key: String) {
        if collapsedLines.contains(key) {
            collapsedLines.remove(key)
        } else {
            collapsedLines.insert(key)
        }
    }

    private func lineKey(_ family: ModelDisplayNames.Family, _ line: ModelDisplayNames.Line) -> String {
        "\(family.rawValue)/\(line.id)"
    }

    private func columnHeader(nested: Bool) -> some View {
        HStack(spacing: 16) {
            sortHeader(.name, alignment: .leading)
                .padding(.leading, nested ? DashboardTableGroupMetrics.nestedInset : 0)
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            sortHeader(.requests, alignment: .trailing)
                .frame(width: 72, alignment: .trailing)
            sortHeader(.tokens, alignment: .trailing)
                .frame(width: 72, alignment: .trailing)
            sortHeader(.value, alignment: .trailing)
                .frame(width: 72, alignment: .trailing)
            sortHeader(.charged, alignment: .trailing)
                .frame(width: 72, alignment: .trailing)
            sortHeader(.rate, alignment: .trailing)
                .frame(width: 88, alignment: .trailing)
        }
        .padding(.horizontal, DashboardTableGroupMetrics.edgeInset)
        .frame(height: DashboardTableGroupMetrics.columnHeaderHeight)
        .overlay(alignment: .bottom) { rowRule }
    }

    private func modelRow(_ row: ModelPricingRow, nameInset: CGFloat) -> some View {
        let hovered = hoveredIntent == row.modelIntent
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let change = ActivityModelCatalog.rateChange(for: row, timeZone: timeZone) {
                    ModelRateChangeLabel(change: change)
                }
            }
            .padding(.leading, nameInset)
            .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

            Text("\(row.requestCount)")
                .font(CursorProfile.Font.meta.monospacedDigit())
                .frame(width: 72, alignment: .trailing)
            Text(TokenCountFormat.compact(row.tokens))
                .font(CursorProfile.Font.meta.monospacedDigit())
                .frame(width: 72, alignment: .trailing)
            Text(ActivityCostSemantics.formatCents(row.usageValueCents))
                .font(CursorProfile.Font.meta.monospacedDigit())
                .frame(width: 72, alignment: .trailing)
            Text(ActivityCostSemantics.formatCents(row.onDemandChargedCents))
                .font(CursorProfile.Font.meta.monospacedDigit())
                .frame(width: 72, alignment: .trailing)
            Text(row.impliedCentsPerMillion.map(ActivityModelCatalog.formatRate) ?? "—")
                .font(CursorProfile.Font.meta.monospacedDigit())
                .foregroundStyle(row.impliedCentsPerMillion == nil ? Color.secondary : Color.primary)
                .help(ModelPricingCatalog.impliedRateHelp)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 88, alignment: .trailing)
        }
        .padding(.horizontal, DashboardTableGroupMetrics.edgeInset)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovered ? CursorProfile.quaternaryFill(colorScheme) : Color.clear)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .overlay(alignment: .bottom) { rowRule }
        .onHover { hovering in
            hoveredIntent = hovering ? row.modelIntent : (hoveredIntent == row.modelIntent ? nil : hoveredIntent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility(row))
    }

    private var rowRule: some View {
        Rectangle()
            .fill(CursorProfile.hairline(colorScheme, highContrast: false))
            .frame(height: 1)
            .padding(.leading, DashboardTableGroupMetrics.edgeInset)
    }

    private func sortHeader(_ column: DashboardModelSort, alignment: HorizontalAlignment) -> some View {
        DashboardSortHeader(
            title: column.title,
            isActive: sort == column,
            direction: direction,
            alignment: alignment
        ) {
            let next = DashboardModelOrdering.nextSelection(
                current: sort,
                direction: direction,
                tapped: column
            )
            sort = next.0
            direction = next.1
        }
    }

    private func accessibility(_ row: ModelPricingRow) -> String {
        var parts = [
            row.displayName,
            "\(row.requestCount) requests",
            "\(TokenCountFormat.accessibility(row.tokens)) tokens",
            "usage value \(ActivityCostSemantics.formatCents(row.usageValueCents))",
            "on-demand charged \(ActivityCostSemantics.formatCents(row.onDemandChargedCents))",
        ]
        if let rate = row.impliedCentsPerMillion {
            parts.append("implied \(ActivityModelCatalog.formatRate(rate))")
        }
        return parts.joined(separator: ", ")
    }
}
