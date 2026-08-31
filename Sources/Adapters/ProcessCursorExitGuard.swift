import CursorBarDomain
import Foundation

/// Exit guard backed by live Cursor process PIDs.
public struct ProcessCursorExitGuard: CursorExitGuarding, Sendable {
    private let process: any CursorProcessControlling

    public init(process: any CursorProcessControlling) {
        self.process = process
    }

    public var isCursorRunning: Bool {
        !process.mainCursorPIDs().isEmpty
    }
}
