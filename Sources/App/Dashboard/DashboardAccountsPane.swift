import CursorBarDomain
import SwiftUI

struct DashboardAccountsPane: View {
    @Bindable var model: AppModel
    var surface: DashboardSeatSurface
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: CursorProfile.cardPadding) {
            if showsConnectStatus {
                DashboardConnectAccountRow(
                    addAccount: model.presentation.addAccount,
                    model: model
                )
            }
            tableChrome
            switch model.accountLayout {
            case .table:
                DashboardAccountTable(model: model)
            case .detail:
                DashboardAccountsList(model: model, surface: surface)
            }
        }
    }

    private var tableChrome: some View {
        HStack(alignment: .center, spacing: CursorProfile.itemSpacing) {
            if model.accountLayout == .table {
                usageMetricPicker
                    .fixedSize(horizontal: true, vertical: false)
            }
            filterField
            layoutSwitcher
                .fixedSize(horizontal: true, vertical: false)
            addAccountButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usageMetricPicker: some View {
        DashboardPillSegmentedControl(
            selection: $model.accountUsageMetric,
            options: AccountUsageMetric.allCases,
            accessibilityName: "Usage metric"
        ) { metric, _ in
            Text(metric.title)
        }
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Filter accounts", text: $model.accountFilter)
                .textFieldStyle(.plain)
                .font(CursorProfile.Font.table)
                .focusable(true)
            if !model.accountFilter.isEmpty {
                Button {
                    model.accountFilter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 160, maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(CursorProfile.paper(colorScheme), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    CursorProfile.hairline(colorScheme, highContrast: false),
                    lineWidth: 1
                )
        }
        .focusEffectDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter accounts")
    }

    private var layoutSwitcher: some View {
        DashboardPillSegmentedControl(
            selection: $model.accountLayout,
            options: DashboardAccountLayout.allCases,
            accessibilityName: "Account view"
        ) { layout, _ in
            Image(systemName: layout.symbolName)
                .imageScale(.small)
                .frame(width: 16, height: 16)
                .help(layout.title)
                .accessibilityLabel(layout.accessibilityLabel)
        }
    }

    private var addAccountButton: some View {
        Button {
            model.connectAnotherAccount()
        } label: {
            Text(addTitle)
        }
        .buttonStyle(CursorProfilePrimaryButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
        .disabled(connectDisabled)
        .help(model.presentation.addAccount.menuTitle)
        .accessibilityLabel(model.presentation.addAccount.accessibilityLabel)
    }

    private var addTitle: String {
        if connectDisabled {
            return model.presentation.addAccount.menuTitle
        }
        return "Add Account"
    }

    private var connectDisabled: Bool {
        if case .signingIn = model.presentation.addAccount {
            return true
        }
        return false
    }

    private var showsConnectStatus: Bool {
        switch model.presentation.addAccount {
        case .available:
            return false
        case .signingIn, .failed:
            return true
        }
    }
}
