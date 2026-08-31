import CursorBarDomain
import SwiftUI

/// Circle activity grid. Peach intensity. Uses the Insights day list, no invented counts.
struct UsageActivityHeatmapView: View {
    let days: [DayActivity]
    let range: UsageRange
    let timeZone: TimeZone

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private let cell: CGFloat = 10
    private let gap: CGFloat = 3

    var body: some View {
        if grid.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Activity")
                    .font(CursorProfile.Font.section)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        weekdayGutter
                        VStack(alignment: .leading, spacing: gap) {
                            monthRow
                            weeksRow
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
            }
        }
    }

    private var weekdayGutter: some View {
        VStack(alignment: .trailing, spacing: gap) {
            Color.clear.frame(width: 12, height: 12)
            ForEach(0..<7, id: \.self) { row in
                Text(row == 0 ? "M" : row == 2 ? "W" : row == 4 ? "F" : "")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: cell, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }

    private var monthRow: some View {
        HStack(alignment: .center, spacing: gap) {
            ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                Text(week.monthLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: cell, height: 12, alignment: .leading)
                    .opacity(week.monthLabel.isEmpty ? 0 : 1)
            }
        }
        .accessibilityHidden(true)
    }

    private var weeksRow: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                VStack(spacing: gap) {
                    ForEach(week.cells) { item in
                        Circle()
                            .fill(fill(for: item.requests))
                            .frame(width: cell, height: cell)
                            .overlay {
                                if contrast == .increased, item.requests > 0 {
                                    Circle()
                                        .strokeBorder(CursorProfile.peachDeep.opacity(0.7), lineWidth: 0.5)
                                }
                            }
                            .help(item.help)
                    }
                }
            }
        }
    }

    private func fill(for requests: Int) -> Color {
        guard peak > 0 else { return CursorProfile.emptyCell(colorScheme) }
        return CursorProfile.activityFill(
            normalized: Double(requests) / Double(peak),
            scheme: colorScheme
        )
    }

    private var peak: Int {
        days.map(\.requestCount).max() ?? 0
    }

    private var accessibilitySummary: String {
        "Activity heatmap, \(days.filter { $0.requestCount > 0 }.count) active days"
    }

    private var grid: [HeatWeek] {
        Self.buildGrid(days: days, range: range, timeZone: timeZone)
    }

    static func buildGrid(
        days: [DayActivity],
        range: UsageRange,
        timeZone: TimeZone,
        now: Date = Date()
    ) -> [HeatWeek] {
        guard let bounds = dayBounds(days: days, range: range, timeZone: timeZone, now: now) else {
            return []
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        guard let startDate = date(bounds.start, calendar: calendar),
              let endDate = date(bounds.end, calendar: calendar),
              let weekStart = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)
              )
        else {
            return []
        }

        let byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0.requestCount) })
        var weeks: [HeatWeek] = []
        var cursor = weekStart
        var lastMonth = 0
        // Month grids are a few weeks. All-time keeps the first active day
        // and draws up to 80 weeks so a longer history is not clipped.
        let maxWeeks = weekCap(for: range)
        while cursor <= endDate, weeks.count < maxWeeks {
            var cells: [HeatCell] = []
            var monthLabel = ""
            for row in 0..<7 {
                guard let dayDate = calendar.date(byAdding: .day, value: row, to: cursor) else { continue }
                let key = ActivityDayKey.localDay(containing: dayDate, timeZone: timeZone)
                let month = calendar.component(.month, from: dayDate)
                if row == 0, month != lastMonth, key >= bounds.start, key <= bounds.end {
                    monthLabel = String(calendar.shortMonthSymbols[month - 1].prefix(1)).uppercased()
                    lastMonth = month
                }
                let inRange = key >= bounds.start && key <= bounds.end
                let requests = inRange ? (byDay[key] ?? 0) : 0
                cells.append(
                    HeatCell(
                        id: key.isoDate,
                        requests: requests,
                        help: "\(key.isoDate), \(requests) requests"
                    )
                )
            }
            weeks.append(HeatWeek(cells: cells, monthLabel: monthLabel))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    static func dayBounds(
        days: [DayActivity],
        range: UsageRange,
        timeZone: TimeZone,
        now: Date = Date()
    ) -> (start: ActivityDayKey, end: ActivityDayKey)? {
        switch range {
        case .month(let month):
            let start = ActivityDayKey(year: month.year, month: month.month, day: 1)
            let monthEnd = lastLocalDay(of: month, timeZone: timeZone)
            let today = ActivityDayKey.localDay(containing: now, timeZone: timeZone)
            if month == YearMonth.current(now: now, timeZone: timeZone) {
                return (start, today)
            }
            if start > today {
                return nil
            }
            return (start, monthEnd)
        case .allTime:
            let active = days.filter { $0.requestCount > 0 }
            guard let start = active.map(\.day).min(), let end = active.map(\.day).max() else {
                return nil
            }
            return (start, end)
        }
    }

    static func weekCap(for range: UsageRange) -> Int {
        switch range {
        case .month:
            return 6
        case .allTime:
            return 80
        }
    }

    private static func lastLocalDay(of month: YearMonth, timeZone: TimeZone) -> ActivityDayKey {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1))!
        let dayCount = calendar.range(of: .day, in: .month, for: start)!.count
        return ActivityDayKey(year: month.year, month: month.month, day: dayCount)
    }

    private static func date(_ key: ActivityDayKey, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: key.year, month: key.month, day: key.day))
    }
}

struct HeatWeek: Equatable {
    let cells: [HeatCell]
    let monthLabel: String
}

struct HeatCell: Identifiable, Equatable {
    let id: String
    let requests: Int
    let help: String
}
