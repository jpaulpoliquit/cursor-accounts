import CursorBarDomain
import SwiftUI

/// cursor.com/@jpl year grid: 10pt dots, letter months, M/W/F gutter.
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Activity")
                    .font(CursorProfile.Font.section)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 6) {
                        weekdayGutter
                        canvas(layout)
                    }
                }
                .scrollClipDisabled()
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
                let hot = hoveredID == item.id && item.requests > 0
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
           item.requests > 0
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
        "Activity heatmap, \(days.filter { $0.requestCount > 0 }.count) active days"
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
              let weekStart = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)
              )
        else {
            return []
        }

        let byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0.requestCount) })
        let byTokens = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0.tokens) })
        var weeks: [HeatWeek] = []
        var cursor = weekStart
        var lastMonth = 0
        let maxWeeks = weekCap(for: range)
        while cursor <= endDate, weeks.count < maxWeeks {
            var cells: [HeatCell] = []
            var monthLabel = ""
            for row in 0..<7 {
                guard let dayDate = calendar.date(byAdding: .day, value: row, to: cursor) else { continue }
                let key = ActivityDayKey.localDay(containing: dayDate, timeZone: timeZone)
                let month = calendar.component(.month, from: dayDate)
                if row == 0, month != lastMonth, key >= bounds.start, key <= bounds.end {
                    monthLabel = Self.monthAbbreviation(month: month, calendar: calendar)
                    lastMonth = month
                }
                let inRange = key >= bounds.start && key <= bounds.end
                let requests = inRange ? (byDay[key] ?? 0) : 0
                let tokens = inRange ? (byTokens[key] ?? 0) : 0
                cells.append(
                    HeatCell(
                        id: key.isoDate,
                        requests: requests,
                        tokens: tokens,
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

    /// cursor.com/@jpl: Mon / Wed / Fri initials, Monday-first weeks.
    static func weekdayGutterLabels() -> [String] {
        ["M", "", "W", "", "F", "", ""]
    }

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

struct HeatmapLayout: Equatable {
    let grid: [HeatWeek]
    let peak: Int
    let cell: CGFloat
    let gap: CGFloat
    let monthRowHeight: CGFloat

    var weeksWidth: CGFloat {
        let n = CGFloat(grid.count)
        guard n > 0 else { return 0 }
        return n * cell + (n - 1) * gap
    }

    var height: CGFloat {
        monthRowHeight + gap + 7 * cell + 6 * gap
    }

    func cellOrigin(week: Int, row: Int) -> CGPoint {
        CGPoint(
            x: CGFloat(week) * (cell + gap),
            y: monthRowHeight + gap + CGFloat(row) * (cell + gap)
        )
    }

    func cell(at point: CGPoint) -> HeatCell? {
        guard !grid.isEmpty else { return nil }
        let stride = cell + gap
        let week = Int(floor(point.x / stride))
        let row = Int(floor((point.y - monthRowHeight - gap) / stride))
        guard grid.indices.contains(week), (0..<7).contains(row) else { return nil }
        let origin = cellOrigin(week: week, row: row)
        let rect = CGRect(origin: origin, size: CGSize(width: cell, height: cell))
        guard rect.contains(point) else { return nil }
        let cells = grid[week].cells
        guard cells.indices.contains(row) else { return nil }
        return cells[row]
    }

    func cell(id: String) -> HeatCell? {
        for week in grid {
            if let match = week.cells.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    func frame(of id: String) -> CGRect? {
        for (weekIndex, week) in grid.enumerated() {
            if let row = week.cells.firstIndex(where: { $0.id == id }) {
                return CGRect(
                    origin: cellOrigin(week: weekIndex, row: row),
                    size: CGSize(width: cell, height: cell)
                )
            }
        }
        return nil
    }

    func fill(_ item: HeatCell, scheme: ColorScheme) -> Color {
        guard peak > 0 else { return CursorProfile.emptyCell(scheme) }
        return CursorProfile.activityFill(
            normalized: Double(item.requests) / Double(peak),
            scheme: scheme
        )
    }

    static func make(
        days: [DayActivity],
        range: UsageRange,
        timeZone: TimeZone,
        cell: CGFloat,
        gap: CGFloat,
        now: Date = Date()
    ) -> HeatmapLayout {
        let grid = UsageActivityHeatmapView.buildGrid(
            days: days,
            range: range,
            timeZone: timeZone,
            now: now
        )
        return HeatmapLayout(
            grid: grid,
            peak: days.map(\.requestCount).max() ?? 0,
            cell: cell,
            gap: gap,
            monthRowHeight: 12
        )
    }
}

struct HeatWeek: Equatable {
    let cells: [HeatCell]
    let monthLabel: String
}

struct HeatCell: Identifiable, Equatable {
    let id: String
    let requests: Int
    let tokens: Int64
    let help: String
}
