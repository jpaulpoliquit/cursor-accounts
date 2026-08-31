import CursorBarDomain
import SwiftUI

/// Variant B — Settings-style left rail. Hierarchy, not a public profile.
struct DashboardSettingsRailView: View {
    @Bindable var model: AppModel
    var dashboardVisible: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            rail
            Rectangle()
                .fill(CursorProfile.hairline(colorScheme, highContrast: false))
                .frame(width: 1)
            ScrollView {
                DashboardTabBody(
                    model: model,
                    dashboardVisible: dashboardVisible,
                    accountsSurface: .card
                )
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(CursorProfile.page(colorScheme))
        }
        .animation(Motion.gentle(reduceMotion: reduceMotion), value: model.dashboardTab)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ProductName.display)
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 10)
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                railButton(tab)
            }
            Spacer(minLength: 0)
        }
        .frame(width: CursorProfile.railWidth, alignment: .topLeading)
        .background(CursorProfile.elevated(colorScheme))
    }

    private func railButton(_ tab: DashboardTab) -> some View {
        let selected = tab == model.dashboardTab
        return Button {
            model.dashboardTab = tab
        } label: {
            HStack(spacing: 10) {
                Capsule()
                    .fill(selected ? CursorProfile.chartAccent : Color.clear)
                    .frame(width: 3, height: 16)
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.trailing, 12)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? CursorProfile.quaternaryFill(colorScheme) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
