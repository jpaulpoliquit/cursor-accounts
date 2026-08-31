import AppKit
import CursorBarDomain
import SwiftUI

/// Dashboard auth chrome + account-actions menu. Emits the same AppModel intents as the menu.
struct DashboardSeatControls: View {
    let seat: SeatPresentation
    let hardLimitPhase: SetHardLimitPhase
    let model: AppModel

    private var projection: DashboardSeatControlsProjection {
        .project(seat: seat, hardLimitPhase: hardLimitPhase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            authSection
            if case .available(_, _, _, let statusText, _) = projection.onDemand,
               let statusText
            {
                Text(statusText)
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(
                        statusText.hasPrefix("Saved") || statusText == "Saving…"
                            ? Color.secondary
                            : Color.orange
                    )
            }
        }
    }

    @ViewBuilder
    private var authSection: some View {
        switch projection.auth {
        case .signIn:
            Button("Sign In") {
                model.beginSignIn(seatID: seat.seatID)
            }
            .buttonStyle(CursorProfilePrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)

        case .signingIn(let canCancel):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Signing in…")
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
                if canCancel {
                    Button("Cancel") {
                        model.cancelSignIn(seatID: seat.seatID)
                    }
                    .buttonStyle(.borderless)
                }
            }

        case .reauthenticate:
            Button("Reauthenticate") {
                model.reauthenticate(seatID: seat.seatID)
            }
            .buttonStyle(CursorProfilePrimaryButtonStyle())

        case .signedIn:
            EmptyView()
        }

        if let detail = seat.authDetail {
            Text(detail)
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(detail)
        }
    }
}

/// Header ellipsis: on-demand mode checks + Sign Out. Confirmation stays on AppModel intents.
struct DashboardAccountActionsMenu: View {
    let seat: SeatPresentation
    let hardLimitPhase: SetHardLimitPhase
    let model: AppModel

    private var projection: DashboardSeatControlsProjection {
        .project(seat: seat, hardLimitPhase: hardLimitPhase)
    }

    var body: some View {
        if projection.showsAccountActionsMenu {
            Menu {
                if case .available(_, let selection, let fixedTitle, _, let writesDisabled) =
                    projection.onDemand
                {
                    Section("On-demand") {
                        Button("Edit on-demand…") {
                            model.presentOnDemandEditor(seatID: seat.seatID)
                        }
                        .disabled(writesDisabled)

                        Button {
                            model.requestSetOnDemand(seatID: seat.seatID, mode: .off)
                        } label: {
                            checkLabel("On-demand Off", selected: selection == .off)
                        }
                        .disabled(writesDisabled)

                        Button {
                            model.requestSetOnDemandFixed(seatID: seat.seatID)
                        } label: {
                            checkLabel(fixedTitle, selected: selection == .fixed)
                        }
                        .disabled(writesDisabled)

                        Button {
                            model.requestSetOnDemand(seatID: seat.seatID, mode: .unlimited)
                        } label: {
                            checkLabel("Unlimited", selected: selection == .unlimited)
                        }
                        .disabled(writesDisabled)

                        Button("Set fixed limit…") {
                            model.requestSetOnDemandFixed(seatID: seat.seatID)
                        }
                        .disabled(writesDisabled)
                    }
                }

                Button("Show in Dashboard") {
                    model.focus(seatID: seat.seatID)
                }

                Button("Open Cursor Settings") {
                    if let url = URL(string: "https://cursor.com/settings") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Connect another account") {
                    model.connectAnotherAccount()
                }

                if !seat.isDesktopBound, seat.auth == .signedIn || seat.auth == .needsReauth {
                    Button(seat.openCursorAsSeatTitle) {
                        model.openCursorAsSeat(seatID: seat.seatID)
                    }
                    .disabled(model.presentation.ideSwitchPhase.blocksOtherOpenActions)
                }

                Divider()

                Button("Sign Out from \(ProductName.display)", role: .destructive) {
                    model.requestSignOutLocally(seatID: seat.seatID)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(projection.accountActionsAccessibilityLabel)
            .help(projection.accountActionsAccessibilityLabel)
        }
    }

    @ViewBuilder
    private func checkLabel(_ title: String, selected: Bool) -> some View {
        let row = HStack {
            Text(title)
            if selected {
                Spacer(minLength: 12)
                Text("✓")
                    .accessibilityLabel("Selected")
            }
        }
        .accessibilityElement(children: .combine)

        if selected {
            row.accessibilityAddTraits(.isSelected)
        } else {
            row
        }
    }
}
