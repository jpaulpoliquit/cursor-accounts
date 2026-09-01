import Foundation

/// Chart edge and tooltip dates. Year only when the day is not this calendar year.
public enum UsageChartDateLabel {
    public static func edge(
        _ date: Date,
        now: Date,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        let includeYear = calendar.component(.year, from: date) != calendar.component(.year, from: now)
        var style = Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        .month(.abbreviated)
        .day()
        if includeYear {
            style = style.year()
        }
        return date.formatted(style)
    }
}
