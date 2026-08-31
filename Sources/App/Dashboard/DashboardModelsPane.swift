import CursorBarDomain
import SwiftUI

struct DashboardModelsPane: View {
    @Bindable var model: AppModel
    var dashboardVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CursorProfile.sectionSpacing) {
            if dashboardVisible {
                UsageRangeControls(coordinator: model.usageSeries, showsScope: true)
                catalog
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
