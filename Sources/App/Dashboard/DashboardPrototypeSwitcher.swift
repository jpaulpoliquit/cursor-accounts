#if DEBUG
import AppKit
import SwiftUI

/// Throwaway arena bar. Hidden in Release. Not part of the design under test.
struct DashboardPrototypeSwitcher: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                cycle(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous layout prototype")

            Text(model.dashboardLayoutPrototype.switcherName)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(minWidth: 168)

            Button {
                cycle(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next layout prototype")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black)
        .foregroundStyle(Color.white)
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 2)
        .padding(.bottom, 14)
        .onKeyPress(.leftArrow) {
            guard !isEditingText else { return .ignored }
            cycle(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isEditingText else { return .ignored }
            cycle(1)
            return .handled
        }
    }

    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func cycle(_ delta: Int) {
        let all = DashboardLayoutPrototype.allCases
        guard let index = all.firstIndex(of: model.dashboardLayoutPrototype) else { return }
        let next = (index + delta + all.count) % all.count
        model.dashboardLayoutPrototype = all[next]
    }
}
#endif
