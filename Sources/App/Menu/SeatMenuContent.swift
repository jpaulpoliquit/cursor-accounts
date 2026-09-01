import CursorBarDomain
import SwiftUI

struct SeatMenuContent: View {
    let seat: SeatPresentation
    let model: AppModel

    private var row: AccountMenuRowModel { seat.menuRow }

    var body: some View {
        AccountMenuDetailHeader(row: row)

        if let detail = seat.authDetail {
            Text(detail)
                .foregroundStyle(.orange)
        }

        if seat.loginPhase.isInFlight {
            Button("Cancel Sign-In") {
                model.cancelSignIn(seatID: seat.seatID)
            }
        }

        Divider()

        if seat.auth == .signedIn || seat.auth == .needsReauth {
            Button(seat.userLabel == nil ? "Set label…" : "Edit label…") {
                model.presentLabelEditor(seatID: seat.seatID)
            }
        }

        Button {
            model.focus(seatID: seat.seatID)
        } label: {
            HStack {
                Text(seat.isFocused ? "Shown in Dashboard" : "Show in Dashboard")
                if seat.isFocused {
                    Spacer()
                    Text("✓")
                }
            }
        }

        Button("Refresh") {
            model.refresh(seatID: seat.seatID)
        }

        openCursorAction

        authAction

        if seat.auth == .signedIn || seat.auth == .needsReauth {
            onDemandSubmenu
        }
    }

    @ViewBuilder
    private var openCursorAction: some View {
        let phase = model.presentation.ideSwitchPhase
        if !seat.isDesktopBound, seat.auth == .signedIn || seat.auth == .needsReauth {
            Button(seat.openCursorAsSeatTitle) {
                model.openCursorAsSeat(seatID: seat.seatID)
            }
            .disabled(phase.blocksOtherOpenActions)
        }

        if let status = phase.menuStatusText,
           let target = phase.targetSeatID,
           target == seat.seatID
        {
            Text(status)
                .foregroundStyle(phase.allowsForceQuit ? Color.orange : Color.secondary)
        }
    }

    @ViewBuilder
    private var authAction: some View {
        switch seat.auth {
        case .signedOut:
            Button("Sign In") {
                model.beginSignIn(seatID: seat.seatID)
            }
        case .signingIn:
            Button("Signing In…") {}
                .disabled(true)
        case .needsReauth:
            Button("Reauthenticate") {
                model.reauthenticate(seatID: seat.seatID)
            }
        case .signedIn:
            Button("Sign Out Locally") {
                model.requestSignOutLocally(seatID: seat.seatID)
            }
        }
    }

    @ViewBuilder
    private var onDemandSubmenu: some View {
        Menu("On-Demand") {
            Button {
                model.requestSetOnDemand(seatID: seat.seatID, mode: .off)
            } label: {
                checkLabel("Off", selected: {
                    if case .off = seat.onDemand?.mode { return true }
                    return false
                }())
            }
            Button {
                model.requestSetOnDemandFixed(seatID: seat.seatID)
            } label: {
                let title: String = {
                    if case .fixed(let dollars) = seat.onDemand?.mode {
                        return "Fixed $\(dollars.amount)…"
                    }
                    return "Fixed…"
                }()
                checkLabel(title, selected: {
                    if case .fixed = seat.onDemand?.mode { return true }
                    return false
                }())
            }
            Button {
                model.requestSetOnDemand(seatID: seat.seatID, mode: .unlimited)
            } label: {
                checkLabel("Unlimited", selected: {
                    if case .unlimited = seat.onDemand?.mode { return true }
                    return false
                }())
            }

            if let status = model.presentation.setHardLimitPhase.statusText(for: seat.seatID) {
                Text(status)
                    .foregroundStyle(
                        status.hasPrefix("Saved") || status == "Saving…"
                            ? Color.secondary
                            : Color.orange
                    )
            }
        }
    }

    private func checkLabel(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            if selected {
                Spacer()
                Text("✓")
            }
        }
    }

}
