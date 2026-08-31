import CursorBarAdapters
import CursorBarDomain
import XCTest

final class CachedScopedProfileTests: XCTestCase {
    func testParsesDisplayNameAndPictureURL() {
        let json = """
        {"displayName":"john 5","pictureUrl":"https://example.com/a.png"}
        """
        let profile = CachedScopedProfile.parse(jsonText: json)
        XCTAssertEqual(profile?.displayName?.value, "john 5")
        XCTAssertEqual(profile?.pictureURL?.absoluteString, "https://example.com/a.png")
    }

    func testRejectsEmailShapedDisplayName() {
        let json = #"{"displayName":"a@b.com"}"#
        let profile = CachedScopedProfile.parse(jsonText: json)
        XCTAssertNotNil(profile)
        XCTAssertNil(profile?.displayName)
    }

    func testMalformedJSONIsNonFatalNil() {
        XCTAssertNil(CachedScopedProfile.parse(jsonText: "{not-json"))
        XCTAssertNil(CachedScopedProfile.parse(jsonText: nil))
        XCTAssertNil(CachedScopedProfile.parse(jsonText: ""))
    }

    func testStoredRecordPersistsDisplayNameThroughStoreAndSnapshot() throws {
        let store = UncheckedMemorySeatStore()
        let access = try XCTUnwrap(AccessToken("access-token-value"))
        let refresh = try XCTUnwrap(RefreshToken("refresh-token-value"))
        let record = StoredSeatRecord(
            seatID: .seat1,
            identity: .email(Email("user@example.com")!),
            access: access,
            refresh: refresh,
            email: Email("user@example.com"),
            displayName: DisplayName("john 5"),
            expiresAt: nil,
            membershipType: "ultra",
            subscriptionStatus: "active"
        )
        try store.save(record)
        let loaded = try XCTUnwrap(store.load(seatID: .seat1))
        XCTAssertEqual(loaded.displayName?.value, "john 5")
        XCTAssertEqual(loaded.publicSnapshot().displayName?.value, "john 5")
    }

    func testBootstrapKeepsExistingDisplayNameWhenImportOmitsIt() {
        let existing = DisplayName("kept name")
        let imported: DisplayName? = nil
        let resolved = imported ?? existing
        XCTAssertEqual(resolved?.value, "kept name")
    }
}
