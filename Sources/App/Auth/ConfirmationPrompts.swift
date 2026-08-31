import AppKit
import CursorBarDomain
import Foundation

@MainActor
enum ConfirmationPrompts {
    static func confirmLocalSignOut(accountLabel: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Sign out \(accountLabel) locally?"
        alert.informativeText =
            "Removes this account from \(ProductName.display) only. Cursor desktop storage is not changed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Sign Out Locally")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Privacy-safe: uses AccountLabel text, never invents email local-parts.
    static func confirmOpenCursor(seatID: SeatID, label: AccountLabel?) -> ConfirmedIDEOpen? {
        let alert = NSAlert()
        let name = label?.text ?? "this account"
        alert.messageText = "Switch Cursor to \(name)?"
        alert.informativeText =
            "Restarts Cursor and replaces the signed-in account. Settings, extensions, history, and MCP config stay unchanged."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Switch Account")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return .confirmed(seatID: seatID)
    }

    static func confirmRestorePreviousAccount() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Restore the previous Cursor account?"
        alert.informativeText =
            "Quits Cursor, writes the saved prior session back, then relaunches. Unsaved work in Cursor may be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restore Previous Account")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func confirmForceQuitCursor(prompt: IDEForceQuitPrompt) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Force Quit Cursor?"
        switch prompt {
        case .continueAccountSwitch:
            alert.informativeText =
                "Cursor did not exit in time. Force Quit ends the app immediately, then account switching can continue."
        case .restorePreviousAccountAfterFailedSwitch:
            alert.informativeText =
                "Cursor did not quit after a failed switch; force quitting may discard unsaved work and is required to restore the previous account."
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func confirmOnDemandOff(accountLabel: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Turn off on-demand for \(accountLabel)?"
        alert.informativeText =
            "Disables the overage path. Plan allowances still apply."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Turn Off")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func confirmOnDemandUnlimited(accountLabel: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Set on-demand to Unlimited?"
        alert.informativeText =
            "\(accountLabel) can spend without a fixed monthly cap."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Set Unlimited")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func promptFixedOnDemand(
        accountLabel: String,
        policy: UsagePolicy?
    ) -> OnDemandMode? {
        let alert = NSAlert()
        alert.messageText = "Fixed on-demand amount"
        alert.informativeText = "Enter a positive whole-dollar monthly limit for \(accountLabel)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "e.g. 190"
        alert.accessoryView = field
        alert.addButton(withTitle: "Set Fixed")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else { return nil }
        switch OnDemandAmountValidation.validate(wholeDollars: value, policy: policy) {
        case .success(let dollars):
            return .fixed(dollars)
        case .failure:
            let fail = NSAlert()
            fail.messageText = "Invalid amount"
            fail.informativeText = "Use a positive whole-dollar amount within plan limits."
            fail.alertStyle = .warning
            fail.addButton(withTitle: "OK")
            fail.runModal()
            return nil
        }
    }
}

/// Static methods bridged as an instance gate for the confirmation coordinator.
@MainActor
final class SystemConfirmationGate: ConfirmationGate {
    func confirmLocalSignOut(accountLabel: String) -> Bool {
        ConfirmationPrompts.confirmLocalSignOut(accountLabel: accountLabel)
    }

    func confirmOnDemandOff(accountLabel: String) -> Bool {
        ConfirmationPrompts.confirmOnDemandOff(accountLabel: accountLabel)
    }

    func confirmOnDemandUnlimited(accountLabel: String) -> Bool {
        ConfirmationPrompts.confirmOnDemandUnlimited(accountLabel: accountLabel)
    }

    func promptFixedOnDemand(accountLabel: String, policy: UsagePolicy?) -> OnDemandMode? {
        ConfirmationPrompts.promptFixedOnDemand(accountLabel: accountLabel, policy: policy)
    }
}
