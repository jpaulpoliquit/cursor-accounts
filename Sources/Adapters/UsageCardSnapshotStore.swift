import CursorBarDomain
import Foundation

/// Disk cache of credential-free seat cards. Restart can paint before the next fetch.
public struct UsageCardSnapshotStore: Sendable {
    private let url: URL
    private let fileManager: FileManager

    public init(
        applicationSupportRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let root = CursorBarDataDirectory.applicationSupportRoot(override: applicationSupportRoot)
        self.url = root.appendingPathComponent("usage-cards.json", isDirectory: false)
        self.fileManager = fileManager
    }

    public func load() -> [SeatID: SeatUsageSnapshot] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try inputData()
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            var mapped: [SeatID: SeatUsageSnapshot] = [:]
            for snapshot in envelope.snapshots {
                mapped[snapshot.seatID] = snapshot
            }
            return mapped
        } catch {
            return [:]
        }
    }

    public func write(_ snapshots: [SeatID: SeatUsageSnapshot]) {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let envelope = Envelope(
                snapshots: snapshots.values.sorted { $0.seatID < $1.seatID },
                writtenAt: Date()
            )
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private func inputData() throws -> Data {
        try Data(contentsOf: url)
    }

    private struct Envelope: Codable, Sendable, Equatable {
        var snapshots: [SeatUsageSnapshot]
        var writtenAt: Date
    }
}
