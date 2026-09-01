import CursorBarDomain
import Foundation

extension AppModel {
    func currentUserLabels() -> [SeatID: SeatUserLabel] {
        var emails: [SeatID: Email] = [:]
        for seat in aggregate.seats {
            if let email = seat.email {
                emails[seat.seatID] = email
            }
        }
        return userLabelStore.labels(seatIDs: aggregate.seats.map(\.seatID), emails: emails)
    }

    func presentLabelEditor(seatID: SeatID) {
        if dashboardVisible {
            labelEditorSeatID = seatID
            return
        }
        let seat = presentation.seats.first(where: { $0.seatID == seatID })
        let draft = ConfirmationPrompts.promptAccountLabel(
            current: seat?.userLabel?.value,
            identity: seat?.label.text ?? "this account"
        )
        guard let draft else { return }
        if let reason = SeatUserLabel.rejectionReason(draft) {
            ConfirmationPrompts.alertInvalidLabel(reason)
            return
        }
        setUserLabel(seatID: seatID, raw: draft)
    }

    func dismissLabelEditor() {
        labelEditorSeatID = nil
    }

    func setUserLabel(seatID: SeatID, raw: String?) {
        let record = try? keychain.load(seatID: seatID)
        let email = record?.email ?? aggregate.seats.first(where: { $0.seatID == seatID })?.email
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            userLabelStore.set(label: nil, identity: record?.identity, email: email, seatID: seatID)
        } else if let label = SeatUserLabel(trimmed) {
            userLabelStore.set(label: label, identity: record?.identity, email: email, seatID: seatID)
        } else {
            return
        }
        labelEditorSeatID = nil
        reproject()
    }
}
