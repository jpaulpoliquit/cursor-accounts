import CursorBarDomain
import SwiftUI

/// Variant C — IDE inspector. Segmented chrome, list|detail for accounts, dense panes.
struct DashboardInspectorView: View {
    @Bindable var model: AppModel
    var dashboardVisible: Bool
    @State private var selectedSeatID: SeatID?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $model.dashboardTab) {
                ForEach(DashboardTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityLabel("Dashboard section")

            Rectangle()
                .fill(CursorProfile.hairline(colorScheme, highContrast: false))
                .frame(height: 1)

            pane
        }
        .background(CursorProfile.page(colorScheme))
        .onAppear(perform: selectDefaultSeat)
        .onChange(of: model.presentation.connectedAccounts.map(\.seatID)) { _, _ in
            selectDefaultSeat()
        }
        .animation(Motion.gentle(reduceMotion: reduceMotion), value: model.dashboardTab)
    }

    @ViewBuilder
    private var pane: some View {
        switch model.dashboardTab {
        case .accounts:
            accountsSplit
        case .models:
            ScrollView {
                DashboardModelsPane(model: model, dashboardVisible: dashboardVisible)
                    .padding(16)
            }
        case .usage:
            ScrollView {
                DashboardUsagePane(model: model, dashboardVisible: dashboardVisible)
                    .padding(16)
            }
        }
    }

    private var accountsSplit: some View {
        HSplitView {
            List(selection: $selectedSeatID) {
                ForEach(model.presentation.connectedAccounts) { seat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(seat.dashboardTitle)
                            .font(CursorProfile.Font.handle)
                        if let subtitle = seat.identitySubtitle {
                            Text(subtitle)
                                .font(CursorProfile.Font.meta)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .tag(Optional(seat.seatID))
                }
                AddAccountCard(
                    addAccount: model.presentation.addAccount,
                    model: model,
                    surface: .row
                )
                .tag(Optional<SeatID>.none)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200, idealWidth: 236, maxWidth: 280)

            Group {
                if let seat = selectedSeat {
                    ScrollView {
                        SeatCardView(
                            seat: seat,
                            hardLimitPhase: model.presentation.setHardLimitPhase,
                            model: model,
                            surface: .card
                        )
                        .padding(16)
                    }
                } else {
                    Text("Select an account")
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedSeat: SeatPresentation? {
        guard let selectedSeatID else { return nil }
        return model.presentation.connectedAccounts.first { $0.seatID == selectedSeatID }
    }

    private func selectDefaultSeat() {
        let ids = model.presentation.connectedAccounts.map(\.seatID)
        if let selectedSeatID, ids.contains(selectedSeatID) {
            return
        }
        selectedSeatID = model.presentation.focusedSeat?.seatID ?? ids.first
    }
}
