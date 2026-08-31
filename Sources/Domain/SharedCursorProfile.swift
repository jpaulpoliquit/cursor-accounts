import Foundation

/// One shared Cursor IDE user-data directory. Account switching never launches per-seat profiles.
public struct SharedCursorProfile: Sendable, Equatable, Hashable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    public static func `default`(homeDirectory: URL) -> SharedCursorProfile {
        let root = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Cursor", isDirectory: true)
        return SharedCursorProfile(rootDirectory: root)
    }

    public var stateDatabaseURL: URL {
        rootDirectory
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("globalStorage", isDirectory: true)
            .appendingPathComponent("state.vscdb", isDirectory: false)
    }

    public func isDefault(homeDirectory: URL) -> Bool {
        rootDirectory.path == SharedCursorProfile.default(homeDirectory: homeDirectory).rootDirectory.path
    }
}

extension SharedCursorProfile: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "SharedCursorProfile(root: \(rootDirectory.path))"
    }

    public var debugDescription: String { description }
}
