import CursorBarDomain
import XCTest

final class AgentCLIParserTests: XCTestCase {
    func testDefaultIsList() throws {
        XCTAssertEqual(try AgentCLIParser.parse([]).get(), .list(json: false))
        XCTAssertEqual(try AgentCLIParser.parse(["accounts", "--json"]).get(), .list(json: true))
    }

    func testLabelSetAndClear() throws {
        XCTAssertEqual(
            try AgentCLIParser.parse(["label", "work", "Freelance"]).get(),
            .label(target: "work", text: "Freelance")
        )
        XCTAssertEqual(
            try AgentCLIParser.parse(["label", "clear", "work"]).get(),
            .label(target: "work", text: "")
        )
        XCTAssertEqual(
            try AgentCLIParser.parse(["label", "seat1"]).get(),
            .label(target: "seat1", text: nil)
        )
        XCTAssertEqual(
            try AgentCLIParser.parse(["label", "jp@example.com", "Work"]).get(),
            .label(target: "jp@example.com", text: "Work")
        )
        XCTAssertTrue(AgentCLIParser.helpText.contains("<account|email>"))
    }

    func testUsageFlags() throws {
        XCTAssertEqual(
            try AgentCLIParser.parse(["usage", "--group", "family", "--seat", "work"]).get(),
            .usage(group: .family, seat: "work", json: false)
        )
        XCTAssertEqual(
            try AgentCLIParser.parse(["switch", "personal", "--force"]).get(),
            .switchAccount(target: "personal", force: true)
        )
    }

    func testUnknownCommandAndFlag() {
        XCTAssertThrowsError(try AgentCLIParser.parse(["explode"]).get())
        XCTAssertThrowsError(try AgentCLIParser.parse(["list", "--nope"]).get())
        XCTAssertThrowsError(try AgentCLIParser.parse(["usage", "--group", "bananas"]).get())
    }
}
