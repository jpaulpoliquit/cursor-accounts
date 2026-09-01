import CursorBarDomain
import Foundation

/// Credential-free roster for the CLI. Written on each app reproject.
public struct PublicRosterStore: Sendable {
    private let url: URL
    private let fileManager: FileManager

    public init(
        applicationSupportRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let root = CursorBarDataDirectory.applicationSupportRoot(override: applicationSupportRoot)
        self.url = root.appendingPathComponent("public-roster.json", isDirectory: false)
        self.fileManager = fileManager
    }

    public func load() -> Snapshot? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        } catch {
            return nil
        }
    }

    public func markDesktopBound(_ seatID: SeatID) {
        guard let snapshot = load() else { return }
        var labels: [SeatID: SeatUserLabel] = [:]
        for (raw, text) in snapshot.userLabels {
            if let id = SeatID(rawValue: raw), let label = SeatUserLabel(text) {
                labels[id] = label
            }
        }
        write(
            aggregate: AggregateSnapshot(seats: snapshot.seats),
            userLabels: labels,
            desktopBoundSeatID: seatID
        )
    }

    public func write(
        aggregate: AggregateSnapshot,
        userLabels: [SeatID: SeatUserLabel],
        desktopBoundSeatID: SeatID?
    ) {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var labels: [String: String] = [:]
            for (seatID, label) in userLabels {
                labels[seatID.rawValue] = label.value
            }
            let snapshot = Snapshot(
                seats: aggregate.seats,
                userLabels: labels,
                desktopBoundSeatID: desktopBoundSeatID?.rawValue,
                writtenAt: Date()
            )
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    public struct Snapshot: Codable, Sendable, Equatable {
        public var seats: [SeatSnapshot]
        public var userLabels: [String: String]
        public var desktopBoundSeatID: String?
        public var writtenAt: Date
    }
}
