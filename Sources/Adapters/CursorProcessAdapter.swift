import AppKit
import CursorBarDomain
import Foundation

public protocol CursorProcessControlling: Sendable {
    func mainCursorPIDs() -> [pid_t]
    func argumentListsForMainCursor() -> [[String]]
    func requestGracefulQuit() -> Bool
    func forceQuit()
    func waitUntilMainProcessesExit(timeout: Duration) async -> Bool
    /// Launch the shared Cursor profile. Never accepts seat-specific directories.
    func launch(sharedProfile: SharedCursorProfile, homeDirectory: URL) throws
    func codeLockExists(in userDataDirectory: URL) -> Bool
}

/// Process ops for Cursor.app. Uses Process/NSRunningApplication — never shell strings.
public struct CursorProcessAdapter: CursorProcessControlling {
    public static let defaultCursorExecutable = URL(
        fileURLWithPath: "/Applications/Cursor.app/Contents/MacOS/Cursor",
        isDirectory: false
    )

    /// Observed Cursor desktop bundle id on this machine; also matched via executable path.
    public static let cursorBundleIdentifier = "com.todesktop.230313mzl4w4u92"

    private let executableURL: URL
    private let bundleIdentifier: String
    private let fileManager: FileManager
    private let argumentListsProvider: @Sendable () -> [[String]]
    private let runningApplicationsProvider: @Sendable () -> [NSRunningApplication]
    private let killPID: @Sendable (pid_t, Int32) -> Int32

    public init(
        executableURL: URL = CursorProcessAdapter.defaultCursorExecutable,
        bundleIdentifier: String = CursorProcessAdapter.cursorBundleIdentifier,
        fileManager: FileManager = .default,
        argumentListsProvider: (@Sendable () -> [[String]])? = nil,
        runningApplicationsProvider: (@Sendable () -> [NSRunningApplication])? = nil,
        killPID: (@Sendable (pid_t, Int32) -> Int32)? = nil
    ) {
        self.executableURL = executableURL
        self.bundleIdentifier = bundleIdentifier
        self.fileManager = fileManager
        self.argumentListsProvider =
            argumentListsProvider ?? { CursorDesktopSessionSource.runningMainCursorArgumentLists() }
        self.runningApplicationsProvider =
            runningApplicationsProvider ?? {
                var apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                let byPath = NSWorkspace.shared.runningApplications.filter {
                    $0.executableURL?.path == executableURL.path
                }
                for app in byPath where !apps.contains(where: { $0.processIdentifier == app.processIdentifier }) {
                    apps.append(app)
                }
                return apps
            }
        self.killPID = killPID ?? { pid, signal in kill(pid, signal) }
    }

    public func mainCursorPIDs() -> [pid_t] {
        Array(
            Set(
                runningApplicationsProvider().map(\.processIdentifier)
            )
        ).sorted()
    }

    public func argumentListsForMainCursor() -> [[String]] {
        argumentListsProvider()
    }

    public func requestGracefulQuit() -> Bool {
        let apps = runningApplicationsProvider()
        guard !apps.isEmpty else { return true }
        var issued = false
        for app in apps where app.terminate() {
            issued = true
        }
        return issued
    }

    public func forceQuit() {
        for app in runningApplicationsProvider() {
            _ = app.forceTerminate()
        }
        // AppKit forceTerminate is best-effort. Electron often stays listed.
        _ = Self.escalateRemainingPIDs(mainCursorPIDs(), kill: killPID)
    }

    /// SIGKILL leftover main Cursor PIDs. Never pid 1. Tests inject `kill`.
    static func escalateRemainingPIDs(_ pids: [pid_t], kill: (pid_t, Int32) -> Int32) -> Int {
        var sent = 0
        for pid in pids where pid > 1 {
            if kill(pid, SIGKILL) == 0 {
                sent += 1
            }
        }
        return sent
    }

    public func waitUntilMainProcessesExit(timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if mainCursorPIDs().isEmpty {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return mainCursorPIDs().isEmpty
    }

    public func launch(sharedProfile: SharedCursorProfile, homeDirectory: URL) throws {
        try fileManager.createDirectory(at: sharedProfile.rootDirectory, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = CursorLaunchArguments.sharedProfileArguments(
            for: sharedProfile,
            homeDirectory: homeDirectory
        )
        try process.run()
    }

    public func codeLockExists(in userDataDirectory: URL) -> Bool {
        let lock = userDataDirectory.appendingPathComponent("code.lock", isDirectory: false)
        return fileManager.fileExists(atPath: lock.path)
    }
}

/// Captures exact launch plan for tests without starting Cursor.
public struct CursorLaunchPlan: Sendable, Equatable {
    public let executableURL: URL
    public let arguments: [String]

    public init(
        executableURL: URL,
        sharedProfile: SharedCursorProfile,
        homeDirectory: URL
    ) {
        self.executableURL = executableURL
        self.arguments = CursorLaunchArguments.sharedProfileArguments(
            for: sharedProfile,
            homeDirectory: homeDirectory
        )
    }
}
