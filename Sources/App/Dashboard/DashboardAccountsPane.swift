import CursorBarDomain
import SwiftUI

struct DashboardAccountsPane: View {
    @Bindable var model: AppModel
    var surface: DashboardSeatSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            switch model.accountLayout {
            case .table:
                DashboardAccountTable(model: model)
            case .detail:
                DashboardAccountsList(model: model, surface: surface)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if showsConnectStatus {
                DashboardConnectAccountRow(
                    addAccount: model.presentation.addAccount,
                    model: model
                )
            }
            Spacer(minLength: 8)
            layoutSwitcher
        }
    }

    private var layoutSwitcher: some View {
        Picker("Account view", selection: $model.accountLayout) {
            ForEach(DashboardAccountLayout.allCases, id: \.self) { layout in
                Image(systemName: layout.symbolName)
                    .tag(layout)
                    .help(layout.title)
                    .accessibilityLabel(layout.accessibilityLabel)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 72)
        .accessibilityLabel("Account view")
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
