import AppKit
import CursorBarDomain
import SwiftUI

struct MenuBarRoot: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let presentation = model.presentation

        ideSwitchChrome(presentation)

        Button("Refresh All") {
            model.refreshAll()
        }
        .keyboardShortcut("r")
        .disabled(presentation.ideSwitchPhase.blocksOtherOpenActions)
        .background(MenuBarMenuOpenBridge(onOpen: {
            DashboardWindowPresenter.registerOpenWindow(openWindow)
            model.refreshOnMenuOpen()
        }))

        Divider()

        ForEach(presentation.connectedAccounts) { seat in
            Menu {
                SeatMenuContent(seat: seat, model: model)
            } label: {
                AccountMenuRow(model: seat.menuRow)
            }
        }

        addAccountMenuItem(presentation.addAccount, hasConnectedAccounts: !presentation.connectedAccounts.isEmpty)

        Divider()

        Toggle(
            "Show usage in menu bar",
            isOn: Binding(
                get: { model.menuBarUsage == .usage },
                set: { model.menuBarUsage = $0 ? .usage : .icon }
            )
        )

        Toggle(
            "Mask Email",
            isOn: Binding(
                get: { model.identityPolicy == .maskEmail },
                set: { masked in
                    model.identityPolicy = masked ? .maskEmail : .revealEmail
                }
            )
        )

        Button("Open Dashboard") {
            model.refreshOnDashboardOpen()
            DashboardWindowPresenter.open(using: openWindow)
        }
        .keyboardShortcut("d")

        Divider()

        Button("Show Account Switch Traces") {
            AccountSwitchTraceReveal.open()
        }

        Divider()

        Button(model.updates.menuTitle) {
            Task { await model.updates.checkAndPresent() }
        }
        .disabled(model.updates.isChecking)

        Button("Quit \(ProductName.display)") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private func ideSwitchChrome(_ presentation: AppPresentation) -> some View {
        if let ideStatus = presentation.ideSwitchPhase.menuStatusText {
            Text(ideStatus)
                .foregroundStyle(presentation.ideSwitchPhase.allowsForceQuit ? Color.orange : Color.secondary)
                .disabled(true)
        } else if let reject = model.ideSwitch.lastRejectMessage {
            Text(reject)
                .foregroundStyle(Color.orange)
                .disabled(true)
        }

        if presentation.ideSwitchPhase.allowsKeepCurrentSession {
            Button("Keep Current Cursor Session") {
                model.acknowledgeIDESwitch()
            }
            if case .pendingStartupRecovery = presentation.ideSwitchPhase {
                Button("Restore Previous Account") {
                    model.continuePendingAccountRestore()
                }
            }
        }

        if presentation.ideSwitchPhase.allowsForceQuit {
            Button("Force Quit Cursor") {
                model.forceQuitCursorAfterIDESwitchTimeout()
            }
            if presentation.ideSwitchPhase.forceQuitPrompt == .continueAccountSwitch {
                Button("Dismiss Account Switch") {
                    model.acknowledgeIDESwitch()
                }
            }
        }

        if presentation.ideSwitchPhase.menuStatusText != nil
            || model.ideSwitch.lastRejectMessage != nil
            || presentation.ideSwitchPhase.allowsKeepCurrentSession
            || presentation.ideSwitchPhase.allowsForceQuit
        {
            Divider()
        }
    }

    @ViewBuilder
    private func addAccountMenuItem(
        _ addAccount: AddAccountPresentation,
        hasConnectedAccounts: Bool
    ) -> some View {
        switch addAccount {
        case .available(let title, _), .failed(let title, _, _):
            if hasConnectedAccounts {
                Divider()
            }
            Button {
                model.connectAnotherAccount()
            } label: {
                ConnectAccountMenuRow(title: title)
            }
            .accessibilityLabel(addAccount.accessibilityLabel)
            if case .failed(_, _, let message) = addAccount {
                Text(message)
                    .foregroundStyle(.secondary)
                    .disabled(true)
            }
        case .signingIn(let seatID, let canCancel, _):
            if hasConnectedAccounts {
                Divider()
            }
            Label(addAccount.menuTitle, systemImage: "plus")
                .foregroundStyle(.secondary)
                .accessibilityLabel(addAccount.accessibilityLabel)
            if canCancel {
                Button("Cancel Sign-In") {
                    model.cancelSignIn(seatID: seatID)
                }
            }
        }
    }
}
