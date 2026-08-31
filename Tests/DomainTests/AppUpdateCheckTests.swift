import CursorBarDomain
import XCTest

final class AppUpdateCheckTests: XCTestCase {
    private let installed = AppVersion(major: 0, minor: 1, patch: 0)
    private let page = URL(string: "https://github.com/jpaulpoliquit/multi-cursor/releases/tag/v0.1.1")!

    func testNewerReleaseIsAvailable() {
        let release = PublishedRelease(
            version: AppVersion(major: 0, minor: 1, patch: 1),
            title: "0.1.1",
            notes: "Fixes",
            pageURL: page,
            dmgURL: URL(string: "https://example.test/Cursor-Accounts-0.1.1.dmg")
        )
        XCTAssertEqual(
            AppUpdateCheck.decide(installed: installed, feed: .latest(release)),
            .available(release)
        )
    }

    func testSameOrOlderReleaseIsUpToDate() {
        let same = PublishedRelease(
            version: installed,
            title: "0.1.0",
            notes: "",
            pageURL: page,
            dmgURL: nil
        )
        XCTAssertEqual(
            AppUpdateCheck.decide(installed: installed, feed: .latest(same)),
            .upToDate(installed: installed)
        )
        let older = PublishedRelease(
            version: AppVersion(major: 0, minor: 0, patch: 9),
            title: "0.0.9",
            notes: "",
            pageURL: page,
            dmgURL: nil
        )
        XCTAssertEqual(
            AppUpdateCheck.decide(installed: installed, feed: .latest(older)),
            .upToDate(installed: installed)
        )
    }

    func testEmptyUnauthorizedUnavailableStayDistinct() {
        XCTAssertEqual(
            AppUpdateCheck.decide(installed: installed, feed: .empty),
            .noPublishedRelease
        )
        XCTAssertEqual(
            AppUpdateCheck.decide(installed: installed, feed: .unauthorized),
            .unauthorized
        )
        XCTAssertEqual(
            AppUpdateCheck.decide(installed: installed, feed: .unavailable),
            .unavailable
        )
    }

    func testPicksCursorAccountsDMGOnly() {
        let dmg = URL(string: "https://example.test/Cursor-Accounts-0.1.1.dmg")!
        let picked = ReleaseDMGAsset.url(named: [
            ("checksums.txt", URL(string: "https://example.test/checksums.txt")!),
            ("Cursor-Accounts-0.1.1.dmg", dmg),
        ])
        XCTAssertEqual(picked, dmg)
        XCTAssertNil(
            ReleaseDMGAsset.url(named: [
                ("MultiCursor-0.1.0.dmg", URL(string: "https://example.test/old.dmg")!),
            ])
        )
    }

    func testRestoreClearsAvailableAfterInstallCatchesUp() {
        let release = PublishedRelease(
            version: AppVersion(major: 0, minor: 1, patch: 1),
            title: "0.1.1",
            notes: "",
            pageURL: page,
            dmgURL: nil
        )
        let stored = AppUpdateCheck.available(release)
        XCTAssertEqual(
            AppUpdateCheck.restore(stored, installed: AppVersion(major: 0, minor: 1, patch: 1)),
            .upToDate(installed: AppVersion(major: 0, minor: 1, patch: 1))
        )
        XCTAssertEqual(
            AppUpdateCheck.restore(stored, installed: AppVersion(major: 0, minor: 1, patch: 0)),
            stored
        )
    }

    func testFailedPullKeepsKnownNewerRelease() {
        let release = PublishedRelease(
            version: AppVersion(major: 0, minor: 1, patch: 1),
            title: "0.1.1",
            notes: "",
            pageURL: page,
            dmgURL: nil
        )
        let known = AppUpdateCheck.available(release)
        XCTAssertEqual(
            AppUpdateCheck.merging(previous: known, incoming: .unavailable),
            known
        )
        XCTAssertEqual(
            AppUpdateCheck.merging(previous: known, incoming: .unauthorized),
            known
        )
        XCTAssertEqual(
            AppUpdateCheck.merging(previous: known, incoming: .upToDate(installed: installed)),
            .upToDate(installed: installed)
        )
        XCTAssertEqual(
            AppUpdateCheck.merging(previous: nil, incoming: .unavailable),
            .unavailable
        )
    }

    func testCopyKeepsFeedFailuresDistinct() {
        XCTAssertEqual(AppUpdateCopy.title(.noPublishedRelease), "No published release")
        XCTAssertTrue(AppUpdateCopy.message(.unauthorized).contains("gh auth"))
        XCTAssertEqual(
            AppUpdateCopy.title(.upToDate(installed: installed)),
            "\(ProductName.display) 0.1.0"
        )
    }

    func testQuietRecheckAfterInterval() {
        let now = Date(timeIntervalSince1970: 1_788_192_000)
        XCTAssertTrue(AppUpdateQuietPolicy.shouldRecheck(lastCheck: nil, now: now))
        XCTAssertFalse(
            AppUpdateQuietPolicy.shouldRecheck(
                lastCheck: now.addingTimeInterval(-60),
                now: now
            )
        )
        XCTAssertTrue(
            AppUpdateQuietPolicy.shouldRecheck(
                lastCheck: now.addingTimeInterval(-AppUpdateQuietPolicy.defaultInterval),
                now: now
            )
        )
    }
}
