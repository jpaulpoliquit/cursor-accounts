import CursorBarDomain
import XCTest

final class OnDemandSpendFormatTests: XCTestCase {
    func testFixedExactLine() {
        let line = OnDemandSpendFormat.line(
            mode: .fixed(PositiveDollars(190)!),
            usedCents: AmountCents(cents: 12_620)
        )
        XCTAssertEqual(line, "$126.20 / $190")
    }

    func testUnlimitedLine() {
        XCTAssertEqual(
            OnDemandSpendFormat.line(mode: .unlimited, usedCents: AmountCents(cents: 12_620)),
            "$126.20 · Unlimited"
        )
    }

    func testOffZeroAndResidual() {
        XCTAssertEqual(
            OnDemandSpendFormat.line(mode: .off, usedCents: AmountCents(cents: 0)),
            "On-demand off"
        )
        XCTAssertEqual(
            OnDemandSpendFormat.line(mode: .off, usedCents: nil),
            "On-demand off"
        )
        XCTAssertEqual(
            OnDemandSpendFormat.line(mode: .off, usedCents: AmountCents(cents: 12_620)),
            "On-demand off · $126.20 used"
        )
    }

    func testHardLimitCrossCheckIndividualLimit() {
        let hard = HardLimit.fixed(PositiveDollars(190)!)
        let individualLimit = AmountCents(cents: 19_000)
        XCTAssertEqual(hard.onDemandMode, .fixed(PositiveDollars(190)!))
        XCTAssertEqual(individualLimit.cents, Int64(190) * 100)
    }

    func testProgressClampsOverCapButLabelKeepsTrueUsed() {
        let used = AmountCents(cents: 25_000)
        let limit = PositiveDollars(190)!
        XCTAssertEqual(OnDemandSpendFormat.progressFraction(used: used, limit: limit), 1.0, accuracy: 0.0001)
        XCTAssertEqual(
            OnDemandSpendFormat.line(mode: .fixed(limit), usedCents: used),
            "$250.00 / $190"
        )
    }

    func testPresentationUsesSharedFormatter() {
        let presentation = OnDemandPresentation(
            mode: .fixed(PositiveDollars(190)!),
            usedCents: AmountCents(cents: 12_620)
        )
        XCTAssertEqual(presentation.spendLine, "$126.20 / $190")
        XCTAssertEqual(presentation.modeLabel, "Fixed $190")
        XCTAssertEqual(presentation.fixedProgressFraction!, 12_620.0 / 19_000.0, accuracy: 0.0001)
    }

    func testManagedWithoutUsedOmitsAmount() {
        XCTAssertEqual(
            OnDemandSpendFormat.line(mode: .fixed(PositiveDollars(190)!), usedCents: nil),
            "Fixed $190"
        )
        XCTAssertEqual(
            OnDemandSpendFormat.line(mode: .unlimited, usedCents: nil),
            "Unlimited"
        )
    }
}
