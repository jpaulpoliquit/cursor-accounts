import CursorBarDomain
import SwiftUI

struct DashboardView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DashboardProfileColumnView(model: model, dashboardVisible: model.dashboardVisible)
            .toolbar { toolbarContent }
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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                Text(connectedCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) {
                Text(connectedCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        ToolbarItem(placement: .principal) {
            DashboardProfileTabBar(selection: $model.dashboardTab)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.connectAnotherAccount()
            } label: {
                Label(model.presentation.addAccount.menuTitle, systemImage: "plus")
            }
            .help(model.presentation.addAccount.menuTitle)
            .disabled(connectDisabled)
            .accessibilityLabel(model.presentation.addAccount.accessibilityLabel)
        }
    }

    private var windowTitle: String {
        if let focused = model.presentation.focusedSeat,
           focused.auth == .signedIn || focused.auth == .needsReauth {
            return focused.dashboardTitle
        }
        return "Dashboard"
    }

    private var connectedCopy: String {
        let count = model.presentation.signedInCount
        if count == 0 {
            return "No accounts connected"
        }
        return "\(count) connected"
    }

    private var connectDisabled: Bool {
        if case .signingIn = model.presentation.addAccount {
            return true
        }
        return false
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
