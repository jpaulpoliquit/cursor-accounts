import CursorBarDomain
import SwiftUI

struct SeatLabelEditorSheet: View {
    let seat: SeatPresentation
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var error: String?

    init(seat: SeatPresentation, model: AppModel) {
        self.seat = seat
        self.model = model
        _draft = State(initialValue: seat.userLabel?.value ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account label")
                .font(CursorProfile.Font.display)
            Text(seat.label.text)
                .font(CursorProfile.Font.handle)
                .foregroundStyle(.secondary)
            TextField("Work, personal, client…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onChange(of: draft) { _, _ in
                    error = validationError
                }
            Text("Shown instead of the Cursor name when accounts share one.")
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
            if let error {
                Text(error)
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Clear") {
                    model.setUserLabel(seatID: seat.seatID, raw: "")
                    dismiss()
                }
                .disabled(seat.userLabel == nil && draft.isEmpty)
                Spacer()
                Button("Cancel") {
                    model.dismissLabelEditor()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let error = validationError {
                        self.error = error
                        return
                    }
                    model.setUserLabel(seatID: seat.seatID, raw: draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }

    private var validationError: String? {
        SeatUserLabel.rejectionReason(draft)
    }
}
