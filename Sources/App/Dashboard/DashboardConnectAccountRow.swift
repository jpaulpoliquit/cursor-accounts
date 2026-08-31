import CursorBarDomain
import SwiftUI

/// Notion-style collection action. Lives in the table chrome, not under the last row.
struct DashboardConnectAccountRow: View {
    let addAccount: AddAccountPresentation
    let model: AppModel

    var body: some View {
        switch addAccount {
        case .available(let title, _), .failed(let title, _, _):
            HStack(spacing: 8) {
                if case .failed(_, _, let message) = addAccount {
                    Text(message)
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button {
                    model.connectAnotherAccount()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text(title)
                    }
                    .font(CursorProfile.Font.pill)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(addAccount.accessibilityLabel)
            }
        case .signingIn(let seatID, let canCancel, let isFinishing):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(isFinishing ? "Finishing…" : "Signing in…")
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
                if canCancel {
                    Button("Cancel") {
                        model.cancelSignIn(seatID: seatID)
                    }
                    .buttonStyle(.plain)
                    .font(CursorProfile.Font.meta)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(addAccount.accessibilityLabel)
        }
    }
}
