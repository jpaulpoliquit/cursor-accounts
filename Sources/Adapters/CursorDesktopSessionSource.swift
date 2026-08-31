import CursorBarDomain
import Darwin
import Foundation
import SQLite3

/// Discovers the active Cursor user-data directory and reads session material from state.vscdb (read-only).
public struct CursorDesktopSessionSource: Sendable {
    public enum DiscoveryError: Error, Sendable, Equatable {
        case databaseUnavailable
        case missingTokens
        case malformedTokens
    }

    private let processArgumentsProvider: @Sendable () -> [[String]]
    private let homeDirectory: URL

    public init(
        processArgumentsProvider: (@Sendable () -> [[String]])? = nil,
        homeDirectory: URL? = nil
    ) {
        self.processArgumentsProvider =
            processArgumentsProvider ?? { CursorDesktopSessionSource.runningCursorArgumentLists() }
        self.homeDirectory = homeDirectory ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    public func load() throws -> ImportedDesktopSession? {
        let userDataDir = resolveUserDataDirectory()
        let dbURL = userDataDir
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("globalStorage", isDirectory: true)
            .appendingPathComponent("state.vscdb", isDirectory: false)
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return nil
        }
        let rows = try readAuthRows(from: dbURL)
        guard let accessRaw = rows["cursorAuth/accessToken"],
              let refreshRaw = rows["cursorAuth/refreshToken"]
        else {
            throw DiscoveryError.missingTokens
        }
        guard let access = AccessToken(accessRaw), let refresh = RefreshToken(refreshRaw) else {
            throw DiscoveryError.malformedTokens
        }
        let email = rows["cursorAuth/cachedEmail"].flatMap(Email.init)
        let profile = CachedScopedProfile.parse(jsonText: rows["cursorAuth/cachedScopedProfile"])
        return ImportedDesktopSession(
            access: access,
            refresh: refresh,
            email: email,
            displayName: profile?.displayName,
            pictureURL: profile?.pictureURL ?? JWTClaims.decode(jwt: accessRaw)?.pictureURL,
            membershipType: rows["cursorAuth/stripeMembershipType"],
            subscriptionStatus: rows["cursorAuth/stripeSubscriptionStatus"],
            userDataDir: userDataDir
        )
    }

    public func resolveUserDataDirectory() -> URL {
        for args in processArgumentsProvider() {
            if let dir = Self.userDataDirectory(fromArguments: args) {
                return dir
            }
        }
        return homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Cursor", isDirectory: true)
    }

    /// Parses argv elements. Paths may contain spaces; never whitespace-split a joined command line.
    public static func userDataDirectory(fromArguments arguments: [String]) -> URL? {
        let prefix = "--user-data-dir="
        for argument in arguments {
            if argument.hasPrefix(prefix) {
                let value = String(argument.dropFirst(prefix.count))
                guard !value.isEmpty else { continue }
                return URL(fileURLWithPath: value, isDirectory: true)
            }
            if argument == "--user-data-dir" {
                continue
            }
        }
        if let index = arguments.firstIndex(of: "--user-data-dir"),
           arguments.index(after: index) < arguments.endIndex
        {
            let value = arguments[arguments.index(after: index)]
            guard !value.hasPrefix("-") else { return nil }
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return nil
    }

    private func readAuthRows(from dbURL: URL) throws -> [String: String] {
        let keys = [
            "cursorAuth/accessToken",
            "cursorAuth/refreshToken",
            "cursorAuth/cachedEmail",
            "cursorAuth/cachedScopedProfile",
            "cursorAuth/stripeMembershipType",
            "cursorAuth/stripeSubscriptionStatus",
        ]
        var db: OpaquePointer?
        // Path + READONLY keeps live WAL readability without URI mode encoding footguns.
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw DiscoveryError.databaseUnavailable
        }
        defer { sqlite3_close(db) }

        var result: [String: String] = [:]
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        for key in keys {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                continue
            }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            _ = sqlite3_bind_text(statement, 1, key, -1, transient)
            if sqlite3_step(statement) == SQLITE_ROW {
                let byteCount = Int(sqlite3_column_bytes(statement, 0))
                if byteCount > 0, let blob = sqlite3_column_blob(statement, 0) {
                    let data = Data(bytes: blob, count: byteCount)
                    if let string = String(data: data, encoding: .utf8), !string.isEmpty {
                        result[key] = string
                    }
                }
            }
        }
        return result
    }

    /// All running Cursor-related argv lists (main binary and helpers).
    public static func runningCursorArgumentLists() -> [[String]] {
        var lists: [[String]] = []
        let pids = allPIDs()
        for pid in pids {
            guard let args = argumentList(for: pid), !args.isEmpty else { continue }
            let executable = (args[0] as NSString).lastPathComponent
            let looksLikeCursor =
                executable == "Cursor"
                || executable.hasPrefix("Cursor Helper")
                || args.contains { $0.contains("Cursor.app") }
            guard looksLikeCursor else { continue }
            lists.append(args)
        }
        return lists
    }

    /// Main `Cursor` binary argv lists only (excludes helpers).
    public static func runningMainCursorArgumentLists() -> [[String]] {
        runningCursorArgumentLists().filter { args in
            guard let exec = args.first else { return false }
            let name = (exec as NSString).lastPathComponent
            return name == "Cursor" && !name.hasPrefix("Cursor Helper")
        }
    }

    private static func allPIDs() -> [pid_t] {
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0
        guard sysctl(&name, u_int(name.count), nil, &length, nil, 0) == 0, length > 0 else {
            return []
        }
        let count = length / MemoryLayout<kinfo_proc>.stride
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: count)
        let result = processes.withUnsafeMutableBufferPointer { buffer -> Int32 in
            sysctl(&name, u_int(name.count), buffer.baseAddress, &length, nil, 0)
        }
        guard result == 0 else { return [] }
        let actual = length / MemoryLayout<kinfo_proc>.stride
        return processes.prefix(actual).map(\.kp_proc.p_pid)
    }

    private static func argumentList(for pid: pid_t) -> [String]? {
        var size = 0
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        let ok = buffer.withUnsafeMutableBufferPointer { ptr -> Bool in
            sysctl(&mib, u_int(mib.count), ptr.baseAddress, &size, nil, 0) == 0
        }
        guard ok else { return nil }

        return buffer.withUnsafeBufferPointer { ptr -> [String]? in
            guard let base = ptr.baseAddress else { return nil }
            let argc = base.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
            guard argc > 0 else { return nil }
            var offset = MemoryLayout<Int32>.size
            // Skip executable path (null-terminated), then any extra null padding.
            while offset < size, base[offset] != 0 { offset += 1 }
            while offset < size, base[offset] == 0 { offset += 1 }

            var args: [String] = []
            args.reserveCapacity(Int(argc))
            for _ in 0..<argc {
                if offset >= size { break }
                let start = offset
                while offset < size, base[offset] != 0 { offset += 1 }
                let length = offset - start
                if length > 0 {
                    let data = Data(bytes: base.advanced(by: start), count: length)
                    if let string = String(data: data, encoding: .utf8) {
                        args.append(string)
                    }
                }
                offset += 1
            }
            return args
        }
    }
}

extension CursorDesktopSessionSource.DiscoveryError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .databaseUnavailable: "Cursor state database unavailable"
        case .missingTokens: "Cursor desktop session has no tokens"
        case .malformedTokens: "Cursor desktop session tokens were malformed"
        }
    }
}
