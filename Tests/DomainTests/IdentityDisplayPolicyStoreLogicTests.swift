import CursorBarDomain
import XCTest

/// Policy enum + persistence key contract (store itself lives in App; domain owns the enum).
final class IdentityDisplayPolicyStoreLogicTests: XCTestCase {
    func testPolicyRawValuesAreStableForUserDefaults() {
        XCTAssertEqual(IdentityDisplayPolicy.maskEmail.rawValue, "maskEmail")
        XCTAssertEqual(IdentityDisplayPolicy.revealEmail.rawValue, "revealEmail")
        XCTAssertEqual(IdentityDisplayPolicy(rawValue: "maskEmail"), .maskEmail)
        XCTAssertEqual(IdentityDisplayPolicy.defaultsKey, "identityDisplayPolicy")
    }

    func testMenuBarUsageRawValuesAreStableForUserDefaults() {
        XCTAssertEqual(MenuBarUsageDisplay.icon.rawValue, "icon")
        XCTAssertEqual(MenuBarUsageDisplay.usage.rawValue, "usage")
        XCTAssertEqual(MenuBarUsageDisplay(rawValue: "icon"), .icon)
        XCTAssertFalse(MenuBarUsageDisplay.icon.showsNumbers)
        XCTAssertTrue(MenuBarUsageDisplay.usage.showsNumbers)
    }

}
