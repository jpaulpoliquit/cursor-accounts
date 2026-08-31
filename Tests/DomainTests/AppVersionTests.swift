import CursorBarDomain
import XCTest

final class AppVersionTests: XCTestCase {
    func testParsesMarketingAndTagForms() {
        XCTAssertEqual(AppVersion.parse("0.1.0"), AppVersion(major: 0, minor: 1, patch: 0))
        XCTAssertEqual(AppVersion.parse("v1.2.3"), AppVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(AppVersion.parse("1.4"), AppVersion(major: 1, minor: 4, patch: 0))
        XCTAssertEqual(AppVersion.parse("  V2.0.1  ")?.display, "2.0.1")
    }

    func testRejectsPrereleaseAndJunk() {
        XCTAssertNil(AppVersion.parse("1.2.3-beta"))
        XCTAssertNil(AppVersion.parse("1"))
        XCTAssertNil(AppVersion.parse(""))
        XCTAssertNil(AppVersion.parse("v"))
        XCTAssertNil(AppVersion.parse("1.x.0"))
    }

    func testCompareOrdersSemver() {
        let older = AppVersion.parse("0.1.0")!
        let newer = AppVersion.parse("0.1.1")!
        XCTAssertTrue(older < newer)
        XCTAssertFalse(newer < older)
        XCTAssertEqual(older, AppVersion.parse("0.1.0"))
    }
}
