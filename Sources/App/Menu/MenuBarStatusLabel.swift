import AppKit
import CursorBarDomain
import SwiftUI

/// Menu-bar extra: yellow mark, optional `97 · 100 · $…`.
struct MenuBarStatusLabel: View {
    let presentation: AppPresentation
    var usage: MenuBarUsageDisplay = .usage
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 5) {
            mark
            if let title = visibleTitle {
                Text(title)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.menuBarAccessibilityLabel)
        .onAppear {
            DashboardWindowPresenter.registerOpenWindow(openWindow)
        }
    }

    private var visibleTitle: String? {
        guard usage.showsNumbers else { return nil }
        let label = presentation.menuBarLabel
        if label == ProductName.display { return nil }
        return label
    }

    @ViewBuilder
    private var mark: some View {
        if NSImage(named: "MenuBarMark") != nil {
            Image("MenuBarMark")
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "circle.bottomrighthalf.filled")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(red: 0.96, green: 0.73, blue: 0.26))
                .imageScale(.small)
                .accessibilityHidden(true)
        }
    }
}
