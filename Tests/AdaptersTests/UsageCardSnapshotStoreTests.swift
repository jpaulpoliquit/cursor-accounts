import CursorBarAdapters
import CursorBarDomain
import XCTest

final class UsageCardSnapshotStoreTests: XCTestCase {
    func testRoundTripAndEmptyLoad() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-card-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageCardSnapshotStore(applicationSupportRoot: root)
        XCTAssertEqual(store.load(), [:])

        let snapshot = SeatUsageSnapshot(
            seatID: .seat1,
            plan: PlanInfo(name: "ultra", includedAmountCents: AmountCents(cents: 20_000)),
            period: PeriodUsageDetail(
                usage: PeriodUsage(
                    autoPercentUsed: PercentUsed(unchecked: 10),
                    apiPercentUsed: PercentUsed(unchecked: 20),
                    totalPercentUsed: PercentUsed(unchecked: 15)
                ),
                displayMessage: nil,
                spendLimitUsage: SpendLimitUsage(individualUsed: AmountCents(cents: 0))
            ),
            hardLimit: .off,
            credits: .absent,
            policy: UsagePolicy(canAdjustOnDemand: true),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        store.write([.seat1: snapshot])
        let loaded = store.load()
        XCTAssertEqual(loaded[.seat1], snapshot)
        let data = try Data(contentsOf: root.appendingPathComponent("usage-cards.json"))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("accessToken"))
        XCTAssertFalse(json.contains("Bearer"))
    }
}
