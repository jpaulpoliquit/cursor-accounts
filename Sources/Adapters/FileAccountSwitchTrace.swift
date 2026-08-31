import CursorBarDomain
import Foundation

/// Append-only JSONL switch log. Lives in `~/Library/Logs/CursorBar/account-switch.jsonl`.
public final class FileAccountSwitchTrace: AccountSwitchTracing, @unchecked Sendable {
    public static let defaultDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CursorBar", isDirectory: true)
    }()

    public static let defaultFileURL = defaultDirectory.appendingPathComponent("account-switch.jsonl")

    private let fileURL: URL
    private let lock = NSLock()
    private var didAnnounce = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func live() -> FileAccountSwitchTrace {
        FileAccountSwitchTrace(fileURL: defaultFileURL)
    }

    public func record(_ record: AccountSwitchTraceRecord) {
        lock.lock()
        defer { lock.unlock() }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record),
              var line = String(data: data, encoding: .utf8)
        else { return }
        line.append("\n")
        guard let payload = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        } else {
            try? payload.write(to: fileURL, options: .atomic)
        }
        if !didAnnounce {
            didAnnounce = true
            NSLog("CursorBar switch trace %@", fileURL.path)
        }
    }
}
