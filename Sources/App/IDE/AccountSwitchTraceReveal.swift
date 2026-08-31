import AppKit
import CursorBarAdapters
import Foundation

enum AccountSwitchTraceReveal {
    static func open() {
        let directory = FileAccountSwitchTrace.defaultDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
