import CursorBarDomain
import SwiftUI

struct UsageRangeControls: View {
    @Bindable var coordinator: UsageSeriesCoordinator
    var showsScope: Bool = false

    var body: some View {
        HStack(spacing: 8) {
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

            Button {
                coordinator.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!coordinator.canGoPrevious)
            .accessibilityLabel("Previous month")

            Text(coordinator.rangeTitle)
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(coordinator.range.accessibilityLabel)

            Button {
                coordinator.goToNextMonth()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!coordinator.canGoNext)
            .accessibilityLabel("Next month")

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
