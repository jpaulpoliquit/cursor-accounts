import CursorBarDomain
import SwiftUI

struct DashboardView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DashboardProfileColumnView(model: model, dashboardVisible: model.dashboardVisible)
            .background(
                DashboardWindowAccessor(
                    title: windowTitle,
                    onActivate: { model.refreshOnDashboardOpen() },
                    onClose: { model.noteDashboardClosed() }
                )
            )
            .background { tabShortcuts }
            .onDisappear {
                if DashboardWindowPresenter.findDashboardWindow()?.isVisible != true {
                    model.noteDashboardClosed()
                }
            }
            .animation(Motion.gentle(reduceMotion: reduceMotion), value: model.presentation.signedInCount)
            .animation(Motion.gentle(reduceMotion: reduceMotion), value: model.presentation.addAccount)
            .animation(Motion.gentle(reduceMotion: reduceMotion), value: model.presentation.bootstrapPhase)
            .sheet(item: $model.onDemandEditorSeatID) { seatID in
                if let seat = editorSeat(seatID) {
                    OnDemandEditSheet(seat: seat, model: model)
                }
            }
    }

    private func editorSeat(_ seatID: SeatID) -> SeatPresentation? {
        model.presentation.connectedAccounts.first(where: { $0.seatID == seatID })
            ?? model.presentation.seats.first(where: { $0.seatID == seatID })
    }

    private var windowTitle: String {
        model.dashboardTab.title
    }

    private var tabShortcuts: some View {
        HStack {
            Button("Accounts") { model.dashboardTab = .accounts }
                .keyboardShortcut("1", modifiers: .command)
            Button("Models") { model.dashboardTab = .models }
                .keyboardShortcut("2", modifiers: .command)
            Button("Usage") { model.dashboardTab = .usage }
                .keyboardShortcut("3", modifiers: .command)
        }
        .opacity(0.001)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
