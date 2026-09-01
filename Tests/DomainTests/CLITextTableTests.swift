import CursorBarDomain
import XCTest

final class CLITextTableTests: XCTestCase {
    func testAlignedRowsShareOneWidth() {
        let table = CLITextTable.aligned(
            headers: ["Label", "Email"],
            rows: [
                ["Work", "a@b.com"],
                ["John Paul Poliquit", "jpaulpoliquit@icloud.com"],
            ]
        )
        let lines = table.split(separator: "\n")
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(Set(lines.map(\.count)).count, 1)
        XCTAssertTrue(table.contains("─"))
        XCTAssertTrue(table.contains("jpaulpoliquit@icloud.com"))
    }

    func testPairsPadKeys() {
        let text = CLITextTable.pairs([
            ("input", "2B"),
            ("cacheRead", "40.8B"),
        ])
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasPrefix("input"))
        XCTAssertTrue(lines[1].hasPrefix("cacheRead"))
        XCTAssertTrue(lines[0].contains("  2B"))
        XCTAssertTrue(lines[1].contains("  40.8B"))
    }
}
