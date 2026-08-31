import CursorBarDomain
import Foundation

/// Disk cache of the last compact chart. Restart can paint the dashboard before the next fetch.
public struct UsageChartSnapshotStore: Sendable {
    private let url: URL
    private let fileManager: FileManager

    public init(
        applicationSupportRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let root = CursorBarDataDirectory.applicationSupportRoot(override: applicationSupportRoot)
        self.url = root.appendingPathComponent("usage-chart.json", isDirectory: false)
        self.fileManager = fileManager
    }

    public func load() -> UsageChartSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(UsageChartSnapshot.self, from: data)
            return snapshot.isWellFormed ? snapshot : nil
        } catch {
            return nil
        }
    }

    public func write(_ snapshot: UsageChartSnapshot?) {
        do {
            guard let snapshot else {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
                return
            }
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }
}
