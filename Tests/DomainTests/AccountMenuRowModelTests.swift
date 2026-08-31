import CursorBarDomain
import XCTest

final class AccountMenuRowModelTests: XCTestCase {
    func testTwoLineMetricsKeepUsedPercentSemantics() {
        let seat = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            planName: "ultra",
            autoPercent: PercentUsed(unchecked: 93),
            apiPercent: PercentUsed(unchecked: 100),
            pill: .onDemandActive,
            identityPolicy: .maskEmail
        )
        let row = seat.menuRow
        XCTAssertEqual(row.primaryName, "john 5")
        XCTAssertEqual(row.cursorUsedPercent, 93)
        XCTAssertEqual(row.otherUsedPercent, 100)
        XCTAssertEqual(row.cursorMetricText, "Cursor  93%")
        XCTAssertEqual(row.otherMetricText, "Other 100%")
        XCTAssertTrue(row.secondarySummary.contains("Ultra"))
        XCTAssertTrue(row.secondarySummary.contains("Cursor  93%"))
        XCTAssertTrue(row.secondarySummary.contains("On-demand"))
        XCTAssertEqual(row.pill, .onDemandActive)
        XCTAssertFalse(row.showsActiveIDE)
        XCTAssertFalse(row.helpText.contains("@"))
        XCTAssertTrue(row.accessibilityLabel.contains("john 5"))
    }

    func testRevealPrefersEmailForPrimaryLine() {
        let email = Email("john5@example.com")!
        let seat = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("John Paul Poliquit")!),
            revealedEmail: email,
            auth: .signedIn,
            identityPolicy: .revealEmail
        )
        let row = seat.menuRow
        XCTAssertEqual(row.primaryName, email.value)
        XCTAssertTrue(row.helpText.contains("John Paul Poliquit"))
        XCTAssertTrue(row.helpText.contains(email.value))
    }

    func testMaskNeverLeaksEmailInPrimaryOrHelp() {
        let seat = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("John Paul Poliquit")!),
            revealedEmail: Email("hidden@example.com"),
            auth: .signedIn,
            identityPolicy: .maskEmail
        )
        let row = seat.menuRow
        XCTAssertEqual(row.primaryName, "John Paul Poliquit")
        XCTAssertFalse(row.primaryName.contains("@"))
        XCTAssertFalse(row.helpText.contains("@"))
    }

    func testMissingUsageKeepsAlignedPlaceholders() {
        let seat = SeatPresentation(
            seatID: .seat2,
            label: .displayName(DisplayName("John Paul Poliquit")!),
            auth: .signedIn,
            pill: .onDemandReady,
            usageLoadState: .ready,
            identityPolicy: .maskEmail
        )
        let row = seat.menuRow
        XCTAssertNil(row.cursorUsedPercent)
        XCTAssertNil(row.otherUsedPercent)
        XCTAssertEqual(row.cursorMetricText, "Cursor   —")
        XCTAssertEqual(row.otherMetricText, "Other   —")
        XCTAssertEqual(row.metricsLine, "Cursor   —  Other   —")
        XCTAssertEqual(row.pill, .onDemandReady)
    }

    func testPendingUsageShowsEllipsisNotDash() {
        let seat = SeatPresentation(
            seatID: .seat2,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            usageLoadState: .pending,
            identityPolicy: .maskEmail
        )
        let row = seat.menuRow
        XCTAssertEqual(row.secondarySummary, "Cursor   … · Other   …")
    }

    func testFailedUsageShowsErrorMarker() {
        let seat = SeatPresentation(
            seatID: .seat2,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            usageLoadState: .failed,
            identityPolicy: .maskEmail
        )
        let row = seat.menuRow
        XCTAssertTrue(row.secondarySummary.contains("Cursor  err"))
        XCTAssertTrue(row.secondarySummary.contains("Other  err"))
    }

    func testPartialUsageAndExhaustedPill() {
        let seat = SeatPresentation(
            seatID: .seat3,
            label: .displayName(DisplayName("john paul")!),
            auth: .signedIn,
            autoPercent: PercentUsed(unchecked: 0),
            pill: .exhausted,
            identityPolicy: .maskEmail
        )
        let row = seat.menuRow
        XCTAssertEqual(row.cursorMetricText, "Cursor   0%")
        XCTAssertEqual(row.otherMetricText, "Other   —")
        XCTAssertEqual(row.pill?.shortTitle, "Exhausted")
    }

    func testActiveIDEUsesDesktopBoundOnly() {
        let inactive = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            isFocused: true,
            isDesktopBound: false,
            identityPolicy: .maskEmail
        )
        XCTAssertFalse(inactive.menuRow.showsActiveIDE)

        let active = SeatPresentation(
            seatID: .seat1,
            label: .displayName(DisplayName("john 5")!),
            auth: .signedIn,
            isFocused: false,
            isDesktopBound: true,
            identityPolicy: .maskEmail
        )
        XCTAssertTrue(active.menuRow.showsActiveIDE)
        XCTAssertTrue(active.menuRow.accessibilityLabel.contains("Active"))
        XCTAssertFalse(active.menuRow.accessibilityLabel.contains("Desktop bound"))
    }

    func testLongAliasKeepsFullPrivacySafeHelpText() {
        let long = String(repeating: "A", count: 48)
        let seat = SeatPresentation(
            seatID: .seat4,
            label: .displayName(DisplayName(long)!),
            auth: .signedIn,
            autoPercent: PercentUsed(unchecked: 12),
            apiPercent: PercentUsed(unchecked: 34),
            identityPolicy: .maskEmail
        )
        let row = seat.menuRow
        XCTAssertEqual(row.primaryName, DisplayNameMenuFit.rootTitle(long))
        XCTAssertEqual(row.helpText, long)
        XCTAssertGreaterThan(long.count, DisplayNameMenuFit.maxRootCharacters)
        XCTAssertEqual(DisplayNameMenuFit.rootTitle(long).count, DisplayNameMenuFit.maxRootCharacters)
    }

    func testFiveAccountsProjectIndependently() {
        let seats: [SeatPresentation] = [SeatID.seat1, .seat2, .seat3, .seat4, .seat5].map { id in
            SeatPresentation(
                seatID: id,
                label: .displayName(DisplayName("acct \(id.displayIndex)")!),
                auth: .signedIn,
                autoPercent: PercentUsed(unchecked: Double(id.displayIndex * 10)),
                apiPercent: PercentUsed(unchecked: 100),
                pill: id == .seat1 ? .onDemandReady : .onDemandActive,
                isDesktopBound: id == .seat3,
                identityPolicy: .maskEmail
            )
        }
        XCTAssertEqual(seats.count, 5)
        let rows = seats.map(\.menuRow)
        XCTAssertEqual(rows.map(\.primaryName), ["acct 1", "acct 2", "acct 3", "acct 4", "acct 5"])
        XCTAssertEqual(rows.map(\.cursorUsedPercent), [10, 20, 30, 40, 50])
        XCTAssertEqual(rows.filter(\.showsActiveIDE).count, 1)
        XCTAssertEqual(rows[2].showsActiveIDE, true)
    }
}
