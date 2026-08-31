import Foundation

/// Caller-supplied proof that Cursor main processes are stopped before RW DB access.
public protocol CursorExitGuarding: Sendable {
    var isCursorRunning: Bool { get }
}

public struct ClosureCursorExitGuard: CursorExitGuarding {
    private let check: @Sendable () -> Bool

    public init(_ check: @escaping @Sendable () -> Bool) {
        self.check = check
    }

    public var isCursorRunning: Bool { check() }
}

public struct FixedCursorExitGuard: CursorExitGuarding {
    public let isCursorRunning: Bool

    public init(isCursorRunning: Bool) {
        self.isCursorRunning = isCursorRunning
    }
}
