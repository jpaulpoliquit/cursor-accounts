import CursorBarDomain
import Foundation

/// Persists focused seat. Missing or unknown keys fall back to the first roster seat at project time.
struct FocusedSeatStore {
    private let key = "focusedSeatID"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SeatID {
        guard let raw = defaults.string(forKey: key),
              let seat = SeatID(rawValue: raw)
        else {
            return .seat1
        }
        return seat
    }

    func save(_ seatID: SeatID) {
        defaults.set(seatID.rawValue, forKey: key)
    }
}
