import CursorBarDomain
import XCTest

final class ProfileInitialTests: XCTestCase {
    func testUsesFirstLetterOnly() {
        XCTAssertEqual(ProfileInitial.letter(from: "John Paul Poliquit"), "J")
        XCTAssertEqual(ProfileInitial.letter(from: "john 4"), "J")
        XCTAssertEqual(ProfileInitial.letter(from: "John (Community Software)"), "J")
        XCTAssertEqual(ProfileInitial.letter(from: "cursor@xankeno.com"), "C")
        XCTAssertEqual(ProfileInitial.letter(from: "jhp.poliquit@gmail.com"), "J")
    }

    func testEmptyFallsBack() {
        XCTAssertEqual(ProfileInitial.letter(from: ""), "?")
        XCTAssertEqual(ProfileInitial.letter(from: "4"), "?")
    }
}
