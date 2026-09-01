import CursorBarDomain
import SwiftUI

struct HeatmapLayout: Equatable {
    let grid: [HeatWeek]
    let usesTokens: Bool
    let peak: Double
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

    func intensity(_ item: HeatCell) -> Double {
        usesTokens ? Double(item.tokens) : Double(item.requests)
    }

    func fill(_ item: HeatCell, scheme: ColorScheme) -> Color {
        guard peak > 0 else { return CursorProfile.emptyCell(scheme) }
        return CursorProfile.activityFill(
            normalized: intensity(item) / peak,
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
        let usesTokens = days.contains { $0.tokens > 0 }
        let peak: Double
        if usesTokens {
            peak = Double(days.map(\.tokens).max() ?? 0)
        } else {
            peak = Double(days.map(\.requestCount).max() ?? 0)
        }
        return HeatmapLayout(
            grid: grid,
            usesTokens: usesTokens,
            peak: peak,
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
