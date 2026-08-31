import CursorBarAdapters
import XCTest

final class KeychainServicePolicyTests: XCTestCase {
    func testOwnedServiceNameIsAppCursorBar() {
        XCTAssertEqual(KeychainServicePolicy.ownedServiceName, "app.cursorbar")
    }

    func testForbiddenCursorServiceNamesAreNotWritable() {
        let forbidden = KeychainServicePolicy.forbiddenCursorServiceNames
        XCTAssertTrue(forbidden.contains("cursor-access-token"))
        XCTAssertTrue(forbidden.contains("cursor-refresh-token"))
        XCTAssertTrue(forbidden.contains("Cursor Safe Storage"))
        XCTAssertFalse(forbidden.contains(KeychainServicePolicy.ownedServiceName))
    }

    func testAssertWritableAcceptsOwnedService() {
        KeychainServicePolicy.assertWritable("app.cursorbar")
    }

    func testAssertWritableAcceptsTestPrefix() {
        KeychainServicePolicy.assertWritable("app.cursorbar.test.example")
    }
}
