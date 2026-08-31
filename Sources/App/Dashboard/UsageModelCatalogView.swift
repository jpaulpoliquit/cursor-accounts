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
            VStack(alignment: .leading, spacing: 16) {
                if showsTitle {
                    Text("Models")
                        .font(CursorProfile.Font.section)
                }
                totals
                table
                Text(ModelPricingCatalog.methodologyCopy)
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            HStack(alignment: .top, spacing: 24) {
                totalStats
            }
            VStack(alignment: .leading, spacing: 12) {
                totalStats
            }
        }
    }

    @ViewBuilder
    private var totalStats: some View {
        CursorProfileStat(
            label: ActivityCostSemantics.usageValueLabel,
            value: ActivityCostSemantics.formatCents(catalog.totalUsageValueCents)
        )
        CursorProfileStat(
            label: ActivityCostSemantics.onDemandChargedLabel,
            value: ActivityCostSemantics.formatCents(catalog.totalOnDemandChargedCents)
        )
        CursorProfileStat(
            label: "Subsidized",
            value: ActivityCostSemantics.formatCents(catalog.totalSubsidizedCents)
        )
        .help(ModelPricingCatalog.subsidizedHelp)
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                sortHeader(.name, alignment: .leading)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(CursorProfile.hairline(colorScheme, highContrast: false))
                    .frame(height: 1)
                    .padding(.leading, 14)
            }

            if group == .family {
                ForEach(familySections) { section in
                    familyHeader(section)
                    ForEach(section.rows, id: \.modelIntent) { row in
                        modelRow(row)
                    }
                }
            } else {
                ForEach(rows, id: \.modelIntent) { row in
                    modelRow(row)
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

    private func familyHeader(_ section: ModelFamilySection) -> some View {
        HStack(spacing: 8) {
            Text(section.family.title)
                .font(.system(size: 13, weight: .semibold))
            Text("\(section.rows.count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CursorProfile.hairline(colorScheme, highContrast: false))
                .frame(height: 1)
                .padding(.leading, 14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(section.family.title), \(section.rows.count)")
    }

    private func modelRow(_ row: ModelPricingRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let timeline = ActivityModelCatalog.rateTimelineCaption(for: row, timeZone: timeZone) {
                    Text(timeline)
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
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
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CursorProfile.hairline(colorScheme, highContrast: false))
                .frame(height: 1)
                .padding(.leading, 14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility(row))
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
