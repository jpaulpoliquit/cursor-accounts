import Foundation

/// Stable Keychain and UI identifier for one connected account. Not a fixed-size roster.
public struct SeatID: RawRepresentable, Hashable, Codable, Sendable, Identifiable, Comparable {
    public let rawValue: String

    public var id: SeatID { self }

    public init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.rawValue = trimmed
    }

    public static let seat1 = SeatID(rawValue: "seat1")!
    public static let seat2 = SeatID(rawValue: "seat2")!
    public static let seat3 = SeatID(rawValue: "seat3")!
    public static let seat4 = SeatID(rawValue: "seat4")!
    public static let seat5 = SeatID(rawValue: "seat5")!

    /// Next unused `seatN` key. Fills gaps, then grows.
    public static func next(occupied: some Sequence<SeatID>) -> SeatID {
        let used = Set(occupied)
        var n = 1
        while let candidate = SeatID(rawValue: "seat\(n)"), used.contains(candidate) {
            n += 1
        }
        return SeatID(rawValue: "seat\(n)")!
    }

    /// Preferred seat if empty, otherwise the next unused `seatN`. Occupied probes may fail closed.
    public static func firstEmpty(preferred: SeatID, isOccupied: (SeatID) -> Bool) -> SeatID {
        if !isOccupied(preferred) {
            return preferred
        }
        var n = 1
        while let candidate = SeatID(rawValue: "seat\(n)") {
            if !isOccupied(candidate) {
                return candidate
            }
            n += 1
        }
        return preferred
    }

    public var displayIndex: Int {
        if rawValue.hasPrefix("seat"), let n = Int(rawValue.dropFirst(4)), n > 0 {
            return n
        }
        return Int.max
    }

    public static func < (lhs: SeatID, rhs: SeatID) -> Bool {
        if lhs.displayIndex != rhs.displayIndex {
            return lhs.displayIndex < rhs.displayIndex
        }
        return lhs.rawValue < rhs.rawValue
    }
}
