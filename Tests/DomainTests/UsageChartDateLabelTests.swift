import CursorBarDomain
import XCTest

final class UsageChartDateLabelTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let locale = Locale(identifier: "en_US")

    func testOmitsYearInTheCurrentCalendarYear() {
        let now = date(2026, 9, 1)
        XCTAssertEqual(label(date(2026, 8, 5), now: now), "Aug 5")
        XCTAssertEqual(label(date(2026, 1, 5), now: now), "Jan 5")
    }

    func testIncludesYearWhenTheDayIsLastYear() {
        let now = date(2026, 9, 1)
        XCTAssertEqual(label(date(2025, 8, 5), now: now), "Aug 5, 2025")
    }

    private func label(_ date: Date, now: Date) -> String {
        UsageChartDateLabel.edge(date, now: now, locale: locale, calendar: calendar)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
