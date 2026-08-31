import CursorBarDomain
import SwiftUI

/// Off / Fixed / Unlimited plus the monthly dollar amount. Save applies without a second alert.
struct OnDemandEditSheet: View {
    let seat: SeatPresentation
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft: OnDemandEditorDraft
    @State private var validationError: String?

    init(seat: SeatPresentation, model: AppModel) {
        self.seat = seat
        self.model = model
        _draft = State(initialValue: OnDemandEditorDraft.make(mode: seat.onDemand?.mode, policy: seat.policy))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("On-demand")
                    .font(CursorProfile.Font.display)
                Text(seat.dashboardTitle)
                    .font(CursorProfile.Font.handle)
                    .foregroundStyle(.secondary)
                if let line = seat.onDemand?.spendLine {
                    Text(line)
                        .font(CursorProfile.Font.table.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            DashboardPillSegmentedControl(
                selection: $draft.selection,
                options: [.off, .fixed, .unlimited],
                accessibilityName: "On-demand mode"
            ) { option, _ in
                Text(option.editorTitle)
            }
            .onChange(of: draft.selection) { _, _ in
                validationError = nil
            }

            Text(helperCopy)
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if draft.selection == .fixed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Monthly limit")
                        .font(CursorProfile.Font.statLabel)
                        .foregroundStyle(.secondary)
                    TextField("e.g. 190", text: $draft.fixedText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: draft.fixedText) { _, _ in
                            validationError = nil
                        }
                    if let validationError {
                        Text(validationError)
                            .font(CursorProfile.Font.meta)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let status = model.presentation.setHardLimitPhase.statusText(for: seat.seatID) {
                Text(status)
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(
                        status.hasPrefix("Saved") || status == "Saving…"
                            ? Color.secondary
                            : Color.orange
                    )
            }

            HStack {
                Button("Cancel") {
                    model.dismissOnDemandEditor()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    save()
                }
                .buttonStyle(CursorProfilePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(writesDisabled)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(CursorProfile.paper(colorScheme))
    }

    private var writesDisabled: Bool {
        model.presentation.setHardLimitPhase.disablesWrites(for: seat.seatID)
            || !DashboardSeatControlsProjection.project(
                seat: seat,
                hardLimitPhase: model.presentation.setHardLimitPhase
            ).canPresentOnDemandEditor
    }

    private var helperCopy: String {
        switch draft.selection {
        case .off:
            return "Turns off the overage path. Plan allowances still apply."
        case .fixed:
            return "Caps monthly on-demand spend at a whole-dollar amount."
        case .unlimited:
            return "Allows on-demand spend without a monthly cap."
        }
    }

    private func save() {
        switch draft.resolvedMode(policy: seat.policy) {
        case .success(let mode):
            validationError = nil
            model.commitOnDemandEditor(mode: mode)
            dismiss()
        case .failure(let rejection):
            validationError = Self.message(for: rejection)
        }
    }

    private static func message(for rejection: OnDemandAmountValidation.Rejection) -> String {
        switch rejection {
        case .notPositiveWholeDollars:
            return "Enter a positive whole-dollar amount."
        case .belowPolicyMinimum(let minimum):
            return "Minimum is $\(minimum)."
        case .abovePolicyMaximum(let maximum):
            return "Maximum is $\(maximum)."
        }
    }
}
