import AppKit
import CursorBarDomain
import Foundation

enum UpdateCheckAlert {
    static func present(_ check: AppUpdateCheck) {
        let alert = NSAlert()
        alert.messageText = AppUpdateCopy.title(check)
        alert.informativeText = AppUpdateCopy.message(check)
        alert.alertStyle = .informational
        switch check {
        case .available(let release):
            alert.addButton(withTitle: "View Release")
            if release.dmgURL != nil {
                alert.addButton(withTitle: "Download DMG")
            }
            alert.addButton(withTitle: "Later")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            } else if response == .alertSecondButtonReturn, let dmg = release.dmgURL {
                NSWorkspace.shared.open(dmg)
            }
        case .upToDate, .noPublishedRelease, .unauthorized, .unavailable:
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
