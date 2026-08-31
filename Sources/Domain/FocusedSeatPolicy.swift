/// Focus follows a seat that exists on the roster. Missing stored IDs snap to the first roster seat.
public enum FocusedSeatPolicy {
    public static func resolve(stored: SeatID, roster: [SeatID]) -> SeatID {
        if roster.contains(stored) {
            return stored
        }
        return roster.first ?? stored
    }
}
