import CursorBarDomain
import XCTest

final class HydratedAccountIdentityTests: XCTestCase {
    func testSubjectOnlyIsNotUsable() {
        XCTAssertNil(HydratedAccountIdentity(email: nil, displayName: nil))
    }

    func testFromProfileKeepsPictureAndTeam() {
        let identity = HydratedAccountIdentity.fromProfile(
            emailRaw: "user@example.com",
            firstName: "Ada",
            lastName: nil,
            pictureRaw: "https://example.com/ada.png",
            isTeamAccount: true
        )
        XCTAssertEqual(identity?.pictureURL?.absoluteString, "https://example.com/ada.png")
        XCTAssertEqual(identity?.isTeamAccount, true)
    }

    func testComposeDisplayNameSkipsBlanks() {
        let name = HydratedAccountIdentity.composeDisplayName(firstName: "  john ", lastName: "5")
        XCTAssertEqual(name?.value, "john 5")
        XCTAssertNil(HydratedAccountIdentity.composeDisplayName(firstName: "a@b.com", lastName: nil))
    }

    func testFinishingSignInIsInFlight() {
        XCTAssertTrue(SeatLoginPhase.finishingSignIn.isInFlight)
        XCTAssertEqual(SeatLoginFailure.identityUnavailable.surfaceMessage, "Could not finish sign-in. Try again.")
    }
}
