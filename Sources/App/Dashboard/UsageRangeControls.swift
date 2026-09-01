import CursorBarDomain
import SwiftUI

struct UsageRangeControls: View {
    enum Layout {
        /// Chart header — range title fills the row.
        case hero
        /// Table toolbar — scope, stepper, and calendar hug content.
        case toolbar
    }

    @Bindable var coordinator: UsageSeriesCoordinator
    var showsScope: Bool = false
    var layout: Layout = .hero

    var body: some View {
        HStack(spacing: layout == .toolbar ? 10 : 8) {
            if showsScope {
                Picker("Account", selection: scopeBinding) {
                    ForEach(Array(coordinator.scopeOptions.enumerated()), id: \.offset) { _, option in
                        Text(option.1).tag(option.0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .tint(.secondary)
                .fixedSize()
                .accessibilityLabel("Usage scope")
            }

            HStack(spacing: 6) {
                Button {
                    coordinator.goToPreviousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!coordinator.canGoPrevious)
                .accessibilityLabel("Previous month")

                Text(coordinator.rangeTitle)
                    .font(CursorProfile.Font.table)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: layout == .hero ? .infinity : nil)
                    .fixedSize(horizontal: layout == .toolbar, vertical: false)
                    .accessibilityLabel(coordinator.range.accessibilityLabel)

                Button {
                    coordinator.goToNextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!coordinator.canGoNext)
                .accessibilityLabel("Next month")
            }
            .frame(maxWidth: layout == .hero ? .infinity : nil)

            Menu {
                Button("This month") {
                    coordinator.goToCurrentMonth()
                }
                Button("All time") {
                    coordinator.selectAllTime()
                }
            } label: {
                Image(systemName: "calendar")
            }
            .accessibilityLabel("Usage range menu")

            if coordinator.showsTodayAction {
                Button("Today") {
                    coordinator.goToCurrentMonth()
                }
                .accessibilityLabel("Return to current month")
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .tint(.secondary)
    }

    private var scopeBinding: Binding<UsageScope> {
        Binding(
            get: { coordinator.scope },
            set: { coordinator.selectScope($0) }
        )
    }
}
