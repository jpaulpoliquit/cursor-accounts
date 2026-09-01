import CursorBarDomain
import SwiftUI

/// cursor.com/@jpl year grid: 10pt dots, letter months, M/W/F gutter.
/// One Canvas. Hover uses index math, not a per-cell layout probe.
struct UsageActivityHeatmapView: View {
    let days: [DayActivity]
    let range: UsageRange
    let timeZone: TimeZone

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredID: String?

    private let cell: CGFloat = 10
    private let gap: CGFloat = 2
    private let weekdayGutterWidth: CGFloat = 14

    var body: some View {
        let layout = HeatmapLayout.make(
            days: days,
            range: range,
            timeZone: timeZone,
            cell: cell,
            gap: gap
        )
        if layout.grid.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: CursorProfile.itemSpacing) {
                Text("Activity")
                    .font(CursorProfile.Font.section)
                HStack(alignment: .top, spacing: 6) {
                    weekdayGutter
                    ScrollView(.horizontal, showsIndicators: false) {
                        canvas(layout)
                    }
                    .scrollClipDisabled()
                    .heatmapShowsNewest()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
            }
        }
    }

    private var weekdayGutter: some View {
        VStack(alignment: .trailing, spacing: gap) {
            Color.clear.frame(width: weekdayGutterWidth, height: 12)
            ForEach(Array(Self.weekdayGutterLabels().enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: weekdayGutterWidth, height: cell, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }

    private func canvas(_ layout: HeatmapLayout) -> some View {
        Canvas { context, _ in
            drawHeatmap(context: context, layout: layout)
        }
        .frame(width: layout.weeksWidth, height: layout.height)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hoveredID = layout.cell(at: point)?.id
            case .ended:
                hoveredID = nil
            }
        }
        .overlay {
            hoverCard(layout)
        }
    }

    private func drawHeatmap(context: GraphicsContext, layout: HeatmapLayout) {
        for (weekIndex, week) in layout.grid.enumerated() {
            if !week.monthLabel.isEmpty {
                let origin = layout.cellOrigin(week: weekIndex, row: 0)
                context.draw(
                    Text(week.monthLabel)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary),
                    at: CGPoint(x: origin.x, y: 6),
                    anchor: .leading
                )
            }
            for (row, item) in week.cells.enumerated() {
                let origin = layout.cellOrigin(week: weekIndex, row: row)
                let hot = hoveredID == item.id && layout.intensity(item) > 0
                let scale: CGFloat = hot && !reduceMotion ? 1.08 : 1
                let side = cell * scale
                let rect = CGRect(
                    x: origin.x + (cell - side) / 2,
                    y: origin.y + (cell - side) / 2,
                    width: side,
                    height: side
                )
                context.fill(Path(ellipseIn: rect), with: .color(layout.fill(item, scheme: colorScheme)))
            }
        }
    }

    @ViewBuilder
    private func hoverCard(_ layout: HeatmapLayout) -> some View {
        if let id = hoveredID,
           let frame = layout.frame(of: id),
           let item = layout.cell(id: id),
           layout.intensity(item) > 0
        {
            CursorProfileHoverCard(
                title: hoverTitle(item),
                subtitle: hoverDate(item.id),
                showsPointer: true
            )
            .position(x: frame.midX, y: max(22, frame.minY - 26))
        }
    }

    private func hoverTitle(_ item: HeatCell) -> String {
        if item.tokens > 0 {
            return "\(TokenCountFormat.compact(item.tokens)) tokens"
        }
        return "\(item.requests) requests"
    }

    private func hoverDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return iso }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US")
        guard let date = calendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        ) else { return iso }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var accessibilitySummary: String {
        let active = days.filter { $0.tokens > 0 || $0.requestCount > 0 }.count
        return "Activity heatmap, \(active) active days"
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
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 2
        guard let startDate = date(bounds.start, calendar: calendar),
              let endDate = date(bounds.end, calendar: calendar),
              let firstWeek = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)
              ),
              let lastWeek = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: endDate)
              )
        else {
            return []
        }

        let maxWeeks = weekCap(for: range)
        var weekStarts: [Date] = []
        var cursor = lastWeek
        while cursor >= firstWeek, weekStarts.count < maxWeeks {
            weekStarts.append(cursor)
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        weekStarts.reverse()

        let byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0.requestCount) })
        let byTokens = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0.tokens) })
        var lastMonth = 0
        return weekStarts.map { weekStart in
            var cells: [HeatCell] = []
            var monthLabel = ""
            for row in 0..<7 {
                guard let dayDate = calendar.date(byAdding: .day, value: row, to: weekStart) else { continue }
                let key = ActivityDayKey.localDay(containing: dayDate, timeZone: timeZone)
                let month = calendar.component(.month, from: dayDate)
                if row == 0, month != lastMonth, key >= bounds.start, key <= bounds.end {
                    monthLabel = Self.monthAbbreviation(month: month, calendar: calendar)
                    lastMonth = month
                }
                let inRange = key >= bounds.start && key <= bounds.end
                cells.append(
                    HeatCell(
                        id: key.isoDate,
                        requests: inRange ? (byDay[key] ?? 0) : 0,
                        tokens: inRange ? (byTokens[key] ?? 0) : 0,
                        help: "\(key.isoDate), \(inRange ? (byDay[key] ?? 0) : 0) requests"
                    )
                )
            }
            return HeatWeek(cells: cells, monthLabel: monthLabel)
        }
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
        case .allTime(let start, let end):
            let rangeStart = ActivityDayKey(year: start.year, month: start.month, day: start.day)
            let rangeEnd = ActivityDayKey(year: end.year, month: end.month, day: end.day)
            guard rangeStart <= rangeEnd else { return nil }
            return (rangeStart, rangeEnd)
        }
    }

    static func weekCap(for range: UsageRange) -> Int {
        switch range {
        case .month:
            return 6
        case .allTime:
            return 110
        }
    }

    /// cursor.com/@jpl: Mon / Wed / Fri initials, Monday-first weeks.
    static func weekdayGutterLabels() -> [String] {
        ["M", "", "W", "", "F", "", ""]
    }

    /// Monday-first short weekday names. Tests and accessibility still use these.
    static func weekdayAbbreviations(timeZone: TimeZone, locale: Locale = .current) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        calendar.firstWeekday = 2
        let symbols = calendar.shortWeekdaySymbols
        let origin = calendar.firstWeekday - 1
        return (0..<7).map { row in
            symbols[(origin + row) % symbols.count]
        }
    }

    static func monthAbbreviation(month: Int, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("MMMMM")
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = 1
        guard let date = calendar.date(from: components) else { return "" }
        return formatter.string(from: date)
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

private extension View {
    @ViewBuilder
    func heatmapShowsNewest() -> some View {
        if #available(macOS 15.0, *) {
            self
                .defaultScrollAnchor(.trailing, for: .initialOffset)
                .defaultScrollAnchor(.trailing, for: .sizeChanges)
                .defaultScrollAnchor(.leading, for: .alignment)
        } else {
            defaultScrollAnchor(.trailing)
        }
    }
}
