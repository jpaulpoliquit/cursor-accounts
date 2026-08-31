import CursorBarDomain
import Foundation

/// Advisory hint written after quit and before launch. Never overrides live process truth.
public struct IDESwitchSidecar: Codable, Sendable, Equatable {
    public let seatID: SeatID
    public let userDataDir: String

    public init(seatID: SeatID, userDataDir: URL) {
        self.seatID = seatID
        self.userDataDir = userDataDir.path
    }
}

public struct IDESwitchSidecarStore: Sendable {
    private let url: URL
    private let fileManager: FileManager

    public init(
        applicationSupportRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let root = applicationSupportRoot
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("CursorBar", isDirectory: true)
        self.url = root.appendingPathComponent("active-ide-seat.plist", isDirectory: false)
        self.fileManager = fileManager
    }

    public func load() -> IDESwitchSidecar? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(IDESwitchSidecar.self, from: data)
        } catch {
            return nil
        }
    }

    public func write(_ sidecar: IDESwitchSidecar) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListEncoder().encode(sidecar)
        try data.write(to: url, options: .atomic)
    }
}
