@testable import CursorBar
import XCTest

final class ProfilePictureLoaderTests: XCTestCase {
    func testUnsignedWorkOSRequestForcesJPEG() throws {
        let raw = try XCTUnwrap(URL(string: "https://images.workoscdn.com/user/ada"))
        let request = ProfilePictureLoader.requestURL(for: raw)
        let items = URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "fm" })?.value, "jpg")
        XCTAssertEqual(items.first(where: { $0.name == "w" })?.value, "96")
    }

    func testSignedWorkOSURLIsNotRewritten() throws {
        let raw = try XCTUnwrap(
            URL(string: "https://images.workoscdn.com/user/ada?s=abc&fit=crop")
        )
        XCTAssertEqual(ProfilePictureLoader.requestURL(for: raw), raw)
    }

    func testOtherHostsStayUntouched() throws {
        let raw = try XCTUnwrap(URL(string: "https://lh3.googleusercontent.com/a/ada"))
        XCTAssertEqual(ProfilePictureLoader.requestURL(for: raw), raw)
    }
}
