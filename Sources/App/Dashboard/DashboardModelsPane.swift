import CursorBarDomain
import SwiftUI

struct DashboardModelsPane: View {
    @Bindable var model: AppModel
    var dashboardVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CursorProfile.cardPadding) {
            HStack(alignment: .center, spacing: CursorProfile.itemSpacing) {
                UsageRangeControls(
                    coordinator: model.usageSeries,
                    showsScope: true,
                    layout: .toolbar
                )
                Spacer(minLength: CursorProfile.cardPadding)
                DashboardGroupBySelect(selection: $model.modelGroup)
            }
            if dashboardVisible {
                catalog
            } else {
                Text("Open the dashboard to load model usage.")
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var catalog: some View {
        if let insights = model.usageSeries.insights, !insights.modelCatalog.isEmpty {
            UsageModelCatalogView(
                catalog: insights.modelCatalog,
                timeZone: TimeZone(identifier: insights.timeZoneIdentifier) ?? .current,
                showsTitle: false,
                group: model.modelGroup,
                sort: $model.modelSort,
                direction: $model.modelSortDirection
            )
        } else {
            Text(emptyCopy)
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyCopy: String {
        switch model.usageSeries.insightsPhase {
        case .refreshing:
            return "Loading models…"
        case .idle:
            return "Connect an account to see model usage."
        case .failed(let message):
            return message
        case .settled:
            return "No model activity in this range."
        }
    }
}

/// Newton admin “Group by” field: label + menu trigger, not a checkbox.
private struct DashboardGroupBySelect: View {
    @Binding var selection: DashboardModelGroup
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Text("Group by")
                .font(CursorProfile.Font.table)
                .foregroundStyle(.secondary)
            Menu {
                Picker("Group by", selection: $selection) {
                    ForEach(DashboardModelGroup.allCases, id: \.self) { option in
                        Text(option.menuTitle).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selection.triggerLabel)
                        .font(CursorProfile.Font.table)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(CursorProfile.paper(colorScheme), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            CursorProfile.hairline(colorScheme, highContrast: false),
                            lineWidth: 1
                        )
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Group by")
        .accessibilityValue(selection.triggerLabel)
    }
}
