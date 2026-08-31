import SwiftUI

struct DashboardSeatSurfaceChrome: ViewModifier {
    let surface: DashboardSeatSurface
    var minimumHeight: CGFloat = 160
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        switch surface {
        case .card:
            content
                .padding(CursorProfile.cardPadding)
                .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
                .cursorProfilePaper()
        case .row:
            content
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(CursorProfile.hairline(colorScheme, highContrast: contrast == .increased))
                        .frame(height: 1)
                }
        }
    }
}
