import Foundation

/// Credential-free seat → user-data-dir mapping. Paths only; never tokens.
/// Per-seat directories are deprecated for launch. Prefer `SharedCursorProfile`.
public struct IDEProfileConfig: Codable, Sendable, Equatable {
    /// Absolute path overrides keyed by `SeatID.rawValue`.
    public var pathOverrides: [String: String]

    public init(pathOverrides: [String: String] = [:]) {
        self.pathOverrides = pathOverrides
    }

    public func overridePath(for seatID: SeatID) -> String? {
        pathOverrides[seatID.rawValue]
    }

    public mutating func setOverridePath(_ path: String?, for seatID: SeatID) {
        if let path, !path.isEmpty {
            pathOverrides[seatID.rawValue] = path
        } else {
            pathOverrides.removeValue(forKey: seatID.rawValue)
        }
    }
}

/// Resolves legacy IDE profile directories without touching credentials.
/// New account switching uses `SharedCursorProfile` only.
public enum IDEProfilePaths {
    public static let profilesFolderName = "CursorBar"
    public static let ideProfilesFolderName = "IDEProfiles"

    @available(*, deprecated, message: "Account switching uses SharedCursorProfile; per-seat dirs are not launched.")
    public static func defaultDirectory(
        for seatID: SeatID,
        homeDirectory: URL
    ) -> URL {
        legacyDefaultDirectory(for: seatID, homeDirectory: homeDirectory)
    }

    /// Kept for migration/detection of existing on-disk seat profiles. Do not launch these.
    public static func legacyDefaultDirectory(
        for seatID: SeatID,
        homeDirectory: URL
    ) -> URL {
        let applicationSupport = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        if seatID == .seat1 {
            return SharedCursorProfile.default(homeDirectory: homeDirectory).rootDirectory
        }
        return applicationSupport
            .appendingPathComponent(profilesFolderName, isDirectory: true)
            .appendingPathComponent(ideProfilesFolderName, isDirectory: true)
            .appendingPathComponent("seat-\(seatID.displayIndex)", isDirectory: true)
    }

    @available(*, deprecated, message: "Account switching uses SharedCursorProfile; per-seat dirs are not launched.")
    public static func resolvedDirectory(
        for seatID: SeatID,
        config: IDEProfileConfig,
        homeDirectory: URL
    ) -> URL {
        legacyResolvedDirectory(for: seatID, config: config, homeDirectory: homeDirectory)
    }

    public static func legacyResolvedDirectory(
        for seatID: SeatID,
        config: IDEProfileConfig,
        homeDirectory: URL
    ) -> URL {
        if let override = config.overridePath(for: seatID), !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return legacyDefaultDirectory(for: seatID, homeDirectory: homeDirectory)
    }
}

/// Launch argv for Cursor. Never includes tokens or Keychain material.
public enum CursorLaunchArguments {
    @available(*, deprecated, message: "Prefer sharedProfileArguments(for:homeDirectory:).")
    public static func userDataDirArguments(directory: URL) -> [String] {
        ["--user-data-dir", directory.path]
    }

    /// Default shared profile launches with no `--user-data-dir`.
    /// Non-default shared roots pass that single path only. Never seat-specific dirs.
    public static func sharedProfileArguments(
        for profile: SharedCursorProfile,
        homeDirectory: URL
    ) -> [String] {
        if profile.isDefault(homeDirectory: homeDirectory) {
            return []
        }
        return ["--user-data-dir", profile.rootDirectory.path]
    }
}
