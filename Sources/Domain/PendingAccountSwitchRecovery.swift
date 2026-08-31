import Foundation

/// Versioned identity for one durable switch-recovery journal entry.
/// Secrets live only in the adapter journal payload, never here.
public struct PendingAccountSwitchRecoveryRef: Codable, Sendable, Equatable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let seatID: SeatID
    public let generation: UInt64

    public init(schemaVersion: Int = currentSchemaVersion, seatID: SeatID, generation: UInt64) {
        self.schemaVersion = schemaVersion
        self.seatID = seatID
        self.generation = generation
    }

    public var switchContext: SwitchContext {
        SwitchContext(seatID: seatID, generation: generation)
    }
}
