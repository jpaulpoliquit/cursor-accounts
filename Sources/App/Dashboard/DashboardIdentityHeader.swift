import CursorBarDomain
import SwiftUI

struct DashboardIdentityHeader: View {
    let presentation: AppPresentation
    var compact: Bool = false

    private var focused: SeatPresentation? { presentation.focusedSeat }

    var body: some View {
        HStack(alignment: compact ? .center : .top, spacing: compact ? 8 : 12) {
            if showsIdentity {
                CursorProfileAvatar(
                    name: heroTitle,
                    pictureURL: focused?.pictureURL,
                    size: compact ? 22 : CursorProfile.avatarSize
                )
            }
            VStack(alignment: .leading, spacing: compact ? 1 : 4) {
                Text(heroTitle)
                    .font(compact ? .system(size: 13, weight: .semibold) : CursorProfile.Font.display)
                    .tracking(compact ? 0 : -0.3)
                    .lineLimit(1)
                if !compact, let email = focused?.revealedEmail {
                    Text(email.value)
                        .font(CursorProfile.Font.handle)
                        .foregroundStyle(.secondary)
                }
                Text(headerSubtitle)
                    .font(compact ? .system(size: 11) : CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
    }

    private var helpText: String {
        if let email = focused?.revealedEmail {
            return "\(heroTitle)\n\(email.value)\n\(headerSubtitle)"
        }
        return "\(heroTitle)\n\(headerSubtitle)"
    }

    private var showsIdentity: Bool {
        guard let focused else { return false }
        return focused.auth == .signedIn || focused.auth == .needsReauth
    }

    private var heroTitle: String {
        if showsIdentity, let focused {
            return focused.dashboardTitle
        }
        return ProductName.display
    }

    private var headerSubtitle: String {
        switch presentation.bootstrapPhase {
        case .pending, .running:
            return "Reconciling with your Cursor desktop session…"
        case .settled(.imported), .settled(.refreshed), .settled(.kept):
            let count = presentation.signedInCount
            if count == 0 {
                return "No accounts connected"
            }
            return "\(count) connected"
        case .settled(.noDesktopSession):
            return "No active Cursor desktop session found."
        case .settled(.importFailed):
            return "Desktop import hit a problem. Saved accounts were kept."
        }
    }
}
