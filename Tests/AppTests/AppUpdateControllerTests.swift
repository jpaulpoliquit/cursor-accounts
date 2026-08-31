@testable import CursorBar
import CursorBarAdapters
import CursorBarDomain
import XCTest

@MainActor
final class AppUpdateControllerTests: XCTestCase {
    func testPresentsAvailableAndChangesMenuTitle() async {
        let payload = Data(
            """
            {
              "tag_name": "v0.2.0",
              "name": "0.2.0",
              "body": "Notes",
              "html_url": "https://github.com/jpaulpoliquit/multi-cursor/releases/tag/v0.2.0",
              "assets": [
                {
                  "name": "Cursor-Accounts-0.2.0.dmg",
                  "browser_download_url": "https://example.test/Cursor-Accounts-0.2.0.dmg"
                }
              ]
            }
            """.utf8
        )
        let client = GitHubReleaseClient(
            exchange: { request in
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (payload, response)
            },
            tokenSource: { nil }
        )
        let defaults = UserDefaults(suiteName: "app.cursorbar.test.updates.\(UUID().uuidString)")!
        var presented: AppUpdateCheck?
        let controller = AppUpdateController(
            client: client,
            installed: AppVersion(major: 0, minor: 1, patch: 0),
            defaults: defaults,
            present: { presented = $0 }
        )
        XCTAssertEqual(controller.menuTitle, "Check for Updates…")
        await controller.checkAndPresent()
        XCTAssertEqual(controller.menuTitle, "Update Available…")
        guard case .available(let release) = presented else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(release.version.display, "0.2.0")
    }

    func testRestoresAvailableAcrossRelaunchWithoutRefetch() async {
        let payload = Data(
            """
            {
              "tag_name": "v0.2.0",
              "html_url": "https://github.com/jpaulpoliquit/multi-cursor/releases/tag/v0.2.0",
              "assets": []
            }
            """.utf8
        )
        let suite = "app.cursorbar.test.updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let live = GitHubReleaseClient(
            exchange: { request in
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (payload, response)
            },
            tokenSource: { nil }
        )
        let first = AppUpdateController(
            client: live,
            installed: AppVersion(major: 0, minor: 1, patch: 0),
            defaults: defaults,
            present: { _ in }
        )
        await first.checkAndPresent()
        XCTAssertEqual(first.menuTitle, "Update Available…")

        var fetched = false
        let dead = GitHubReleaseClient(
            exchange: { _ in
                fetched = true
                throw URLError(.notConnectedToInternet)
            },
            tokenSource: { nil }
        )
        let relaunched = AppUpdateController(
            client: dead,
            installed: AppVersion(major: 0, minor: 1, patch: 0),
            defaults: defaults,
            present: { _ in }
        )
        XCTAssertEqual(relaunched.menuTitle, "Update Available…")
        relaunched.quietRecheckIfDue(now: Date())
        XCTAssertFalse(fetched)
        XCTAssertEqual(relaunched.menuTitle, "Update Available…")
    }
}
