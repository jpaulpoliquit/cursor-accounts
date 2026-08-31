import CursorBarDomain
import SwiftUI

/// Compact single connect / signing-in card. Never expands into empty seat slots.
struct AddAccountCard: View {
    let addAccount: AddAccountPresentation
    let model: AppModel
    var surface: DashboardSeatSurface = .card

    var body: some View {
        switch addAccount {
        case .available(let title, _), .failed(let title, _, _):
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(CursorProfile.Font.section)
                if case .failed(_, _, let message) = addAccount {
                    Text(message)
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                }
                Button(title) {
                    model.connectAnotherAccount()
                }
                .buttonStyle(CursorProfilePrimaryButtonStyle())
                .accessibilityLabel(addAccount.accessibilityLabel)
            }
            .modifier(DashboardSeatSurfaceChrome(surface: surface, minimumHeight: 96))
        case .signingIn(let seatID, let canCancel, let isFinishing):
            VStack(alignment: .leading, spacing: 12) {
                Text(isFinishing ? "Finishing sign-in…" : "Signing in…")
                    .font(CursorProfile.Font.section)
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(isFinishing ? "Confirming account identity" : "Complete sign-in in the browser")
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                    if canCancel {
                        Button("Cancel") {
                            model.cancelSignIn(seatID: seatID)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .modifier(DashboardSeatSurfaceChrome(surface: surface, minimumHeight: 96))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(addAccount.accessibilityLabel)
        }
    }
}
