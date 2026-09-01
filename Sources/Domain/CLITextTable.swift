import Foundation

/// Space-padded terminal tables. Tabs do not line up once a cell is long.
public enum CLITextTable {
    public static func aligned(
        headers: [String],
        rows: [[String]],
        gap: String = "  "
    ) -> String {
        let columns = headers.count
        guard columns > 0 else { return rows.map { $0.joined(separator: gap) }.joined(separator: "\n") }
        var widths = headers.map(\.count)
        for row in rows {
            for index in 0..<columns {
                let cell = index < row.count ? row[index] : ""
                widths[index] = max(widths[index], cell.count)
            }
        }
        func pad(_ cells: [String]) -> String {
            (0..<columns).map { index -> String in
                let cell = index < cells.count ? cells[index] : ""
                return cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: gap)
        }
        let rule = widths.map { String(repeating: "─", count: $0) }.joined(separator: gap)
        return ([pad(headers), rule] + rows.map(pad)).joined(separator: "\n")
    }

    public static func alignedRows(headers: [String], rows: [[String]], gap: String = "  ") -> [String] {
        aligned(headers: headers, rows: rows, gap: gap)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    public static func pairRows(_ items: [(String, String)]) -> [String] {
        guard !items.isEmpty else { return [] }
        let width = items.map(\.0.count).max() ?? 0
        return items.map { key, value in
            key.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + value
        }
    }

    public static func pairs(_ items: [(String, String)]) -> String {
        pairRows(items).joined(separator: "\n")
    }
}
