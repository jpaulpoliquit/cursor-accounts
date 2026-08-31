import CursorBarDomain
import XCTest

final class AccountLabelResolverTests: XCTestCase {
    private let sampleEmail = Email("user@example.com")!
    private let sampleDisplayName = DisplayName("Ada Lovelace")!

    func testRevealPrefersDisplayNameThenEmail() {
        let withBoth = AccountLabelResolver.resolve(
            policy: .revealEmail,
            source: .init(seatID: .seat1, email: sampleEmail, displayName: sampleDisplayName)
        )
        XCTAssertEqual(withBoth, .displayName(sampleDisplayName))

        let emailOnly = AccountLabelResolver.resolve(
            policy: .revealEmail,
            source: .init(seatID: .seat2, email: sampleEmail, displayName: nil)
        )
        XCTAssertEqual(emailOnly, .email(sampleEmail))
    }

    func testMaskNeverEmitsEmailOrLocalPart() {
        let cases: [AccountLabelResolver.Source] = [
            .init(seatID: .seat1, email: sampleEmail, displayName: sampleDisplayName),
            .init(seatID: .seat1, email: sampleEmail, displayName: nil),
            .init(seatID: .seat3, email: nil, displayName: nil),
        ]
        for source in cases {
            let label = AccountLabelResolver.resolve(policy: .maskEmail, source: source)
            if case .email = label {
                XCTFail("maskEmail emitted Email for \(source.seatID)")
            }
            XCTAssertFalse(label.text.contains("@"))
            XCTAssertFalse(label.text.contains("user"))
            let secondary = AccountLabelResolver.revealedEmail(policy: .maskEmail, source: source)
            XCTAssertNil(secondary)
        }
    }

    func testMaskFallsBackToCursorAccountWhenNoDisplayName() {
        let label = AccountLabelResolver.resolve(
            policy: .maskEmail,
            source: .init(seatID: .seat1, email: sampleEmail, displayName: nil)
        )
        XCTAssertEqual(label, AccountLabel.cursorAccount(disambiguator: nil))
        XCTAssertEqual(label.text, "Cursor account")
        XCTAssertFalse(label.text.contains("Seat"))
    }

    func testDisambiguatesMultipleUnnamedConnectedAccounts() {
        var labels: [SeatID: AccountLabel] = [
            .seat1: .cursorAccount(disambiguator: nil),
            .seat2: .displayName(sampleDisplayName),
            .seat3: .cursorAccount(disambiguator: nil),
        ]
        AccountLabelResolver.disambiguate(&labels, connected: [.seat1, .seat3])
        XCTAssertEqual(labels[.seat1]?.text, "Cursor account 1")
        XCTAssertEqual(labels[.seat3]?.text, "Cursor account 2")
        XCTAssertEqual(labels[.seat2]?.text, "Ada Lovelace")
    }

    func testDisplayNameRejectsEmptyAndAt() {
        XCTAssertNil(DisplayName(""))
        XCTAssertNil(DisplayName("   "))
        XCTAssertNil(DisplayName("a@b.com"))
        XCTAssertNil(DisplayName("bad@name"))
        XCTAssertEqual(DisplayName(" john 5 ")?.value, "john 5")
    }

    func testMenuFitTruncatesPathologicalNamesOnly() {
        let short = "john 5"
        XCTAssertEqual(DisplayNameMenuFit.rootTitle(short), short)
        let long = String(repeating: "a", count: 40)
        let fitted = DisplayNameMenuFit.rootTitle(long)
        XCTAssertEqual(fitted.count, DisplayNameMenuFit.maxRootCharacters)
        XCTAssertTrue(fitted.hasSuffix("…"))
    }

    func testMenuPrimaryRevealPrefersEmailOverDisplayName() {
        let label = AccountLabelResolver.menuPrimary(
            policy: .revealEmail,
            source: .init(seatID: .seat1, email: sampleEmail, displayName: sampleDisplayName)
        )
        XCTAssertEqual(label, .email(sampleEmail))
    }

    func testMenuPrimaryMaskUsesDisplayNameNeverEmail() {
        let label = AccountLabelResolver.menuPrimary(
            policy: .maskEmail,
            source: .init(seatID: .seat1, email: sampleEmail, displayName: sampleDisplayName)
        )
        XCTAssertEqual(label, .displayName(sampleDisplayName))
        XCTAssertFalse(AccountLabelResolver.menuHelpText(
            policy: .maskEmail,
            menuPrimary: label,
            aliasLabel: label
        ).contains("@"))
    }

    func testMenuHelpIncludesAliasWhenPrimaryIsEmail() {
        let primary = AccountLabel.email(sampleEmail)
        let alias = AccountLabel.displayName(sampleDisplayName)
        let help = AccountLabelResolver.menuHelpText(
            policy: .revealEmail,
            menuPrimary: primary,
            aliasLabel: alias
        )
        XCTAssertTrue(help.contains(sampleEmail.value))
        XCTAssertTrue(help.contains(sampleDisplayName.value))
    }
}
