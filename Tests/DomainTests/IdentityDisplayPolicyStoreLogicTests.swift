import CursorBarDomain
import XCTest

/// Policy enum + persistence key contract (store itself lives in App; domain owns the enum).
final class IdentityDisplayPolicyStoreLogicTests: XCTestCase {
    func testPolicyRawValuesAreStableForUserDefaults() {
        XCTAssertEqual(IdentityDisplayPolicy.maskEmail.rawValue, "maskEmail")
        XCTAssertEqual(IdentityDisplayPolicy.revealEmail.rawValue, "revealEmail")
        XCTAssertEqual(IdentityDisplayPolicy(rawValue: "maskEmail"), .maskEmail)
    }

}
