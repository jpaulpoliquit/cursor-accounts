import CursorBarDomain
import Foundation

struct UsageSeriesChunkKey: Hashable, Sendable {
    let seatID: SeatID
    let year: Int
    let month: Int

    init(seatID: SeatID, month: YearMonth) {
        self.seatID = seatID
        self.year = month.year
        self.month = month.month
    }
}
