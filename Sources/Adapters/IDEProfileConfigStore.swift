import CursorBarDomain
import Foundation

/// Persists seat→user-data-dir overrides without credentials.
public struct IDEProfileConfigStore: Sendable {
    private let url: URL
    private let fileManager: FileManager

    public init(
        applicationSupportRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let root = applicationSupportRoot
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("CursorBar", isDirectory: true)
        self.url = root.appendingPathComponent("ide-profile-config.plist", isDirectory: false)
        self.fileManager = fileManager
    }

    public func load() -> IDEProfileConfig {
        guard fileManager.fileExists(atPath: url.path) else {
            return IDEProfileConfig()
        }
        do {
            let data = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(IDEProfileConfig.self, from: data)
        } catch {
            return IDEProfileConfig()
        }
    }

    public func save(_ config: IDEProfileConfig) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListEncoder().encode(config)
        try data.write(to: url, options: .atomic)
    }
}
