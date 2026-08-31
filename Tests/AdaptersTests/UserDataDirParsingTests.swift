import CursorBarAdapters
import XCTest

final class UserDataDirParsingTests: XCTestCase {
    func testParsesEqualsFormWithSpacesInPath() {
        let args = [
            "/Applications/Cursor.app/Contents/MacOS/Cursor Helper",
            "--type=renderer",
            "--user-data-dir=/Users/test/Library/Application Support/Cursor",
            "--enable-sandbox",
        ]
        let url = CursorDesktopSessionSource.userDataDirectory(fromArguments: args)
        XCTAssertEqual(url?.path, "/Users/test/Library/Application Support/Cursor")
    }

    func testParsesSeparateFlagFormWithSpaces() {
        let args = [
            "Cursor",
            "--user-data-dir",
            "/Users/test/Library/Application Support/Cursor",
            "--foo",
        ]
        let url = CursorDesktopSessionSource.userDataDirectory(fromArguments: args)
        XCTAssertEqual(url?.path, "/Users/test/Library/Application Support/Cursor")
    }

    func testWhitespaceSplitCorruptsPathsWithSpaces() {
        // Caller must supply real argv elements; whitespace-splitting a joined line truncates.
        let broken = "--user-data-dir=/Users/test/Library/Application Support/Cursor"
            .split(separator: " ")
            .map(String.init)
        let corrupted = CursorDesktopSessionSource.userDataDirectory(fromArguments: broken)
        XCTAssertEqual(corrupted?.path, "/Users/test/Library/Application")
        let intact = [
            "--user-data-dir=/Users/test/Library/Application Support/Cursor",
        ]
        XCTAssertEqual(
            CursorDesktopSessionSource.userDataDirectory(fromArguments: intact)?.path,
            "/Users/test/Library/Application Support/Cursor"
        )
    }

    func testFallsBackToDefaultWhenNoFlag() {
        let source = CursorDesktopSessionSource(
            processArgumentsProvider: { [] },
            homeDirectory: URL(fileURLWithPath: "/Users/demo", isDirectory: true)
        )
        let dir = source.resolveUserDataDirectory()
        XCTAssertEqual(
            dir.path,
            "/Users/demo/Library/Application Support/Cursor"
        )
    }
}
