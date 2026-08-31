@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class GitHubReleaseClientTests: XCTestCase {
    private let fixture = Data(
        """
        {
          "tag_name": "v0.1.1",
          "name": "Cursor Accounts 0.1.1",
          "body": "Usage graph fix.",
          "html_url": "https://github.com/jpaulpoliquit/multi-cursor/releases/tag/v0.1.1",
          "draft": false,
          "assets": [
            {
              "name": "checksums.txt",
              "browser_download_url": "https://example.test/checksums.txt"
            },
            {
              "name": "Cursor-Accounts-0.1.1.dmg",
              "browser_download_url": "https://example.test/Cursor-Accounts-0.1.1.dmg"
            }
          ]
        }
        """.utf8
    )

    func testGHLookupUsesKnownInstallPaths() {
        if let path = GitHubReleaseClient.ghExecutable() {
            XCTAssertTrue(path.hasSuffix("/gh"))
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))
        }
    }

    func testParseLatestMapsDMGAndNotes() {
        let result = GitHubReleaseClient.parse(fixture)
        guard case .latest(let release) = result else {
            return XCTFail("expected latest, got \(result)")
        }
        XCTAssertEqual(release.version, AppVersion(major: 0, minor: 1, patch: 1))
        XCTAssertEqual(release.title, "Cursor Accounts 0.1.1")
        XCTAssertEqual(release.notes, "Usage graph fix.")
        XCTAssertEqual(
            release.pageURL.absoluteString,
            "https://github.com/jpaulpoliquit/multi-cursor/releases/tag/v0.1.1"
        )
        XCTAssertEqual(
            release.dmgURL?.absoluteString,
            "https://example.test/Cursor-Accounts-0.1.1.dmg"
        )
    }

    func testFetchAttachesTokenAndTreats404WithTokenAsEmpty() async {
        nonisolated(unsafe) var auth: String?
        let client = GitHubReleaseClient(
            exchange: { request in
                auth = request.value(forHTTPHeaderField: "Authorization")
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(
                    request.url,
                    AppUpdateFeed.githubLatestRelease
                )
                XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data("{}".utf8), response)
            },
            tokenSource: { "test-token" }
        )
        let result = await client.fetchLatest()
        XCTAssertEqual(auth, "Bearer test-token")
        XCTAssertEqual(result, .empty)
    }

    func testFetch404WithoutTokenIsUnauthorized() async {
        let client = GitHubReleaseClient(
            exchange: { request in
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data("{}".utf8), response)
            },
            tokenSource: { nil }
        )
        let result = await client.fetchLatest()
        XCTAssertEqual(result, .unauthorized)
    }

    func testFetch200UsesParser() async {
        let payload = fixture
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
        let result = await client.fetchLatest()
        guard case .latest(let release) = result else {
            return XCTFail("expected latest")
        }
        XCTAssertEqual(release.version.display, "0.1.1")
    }
}
