@testable import CursorBar
import CursorBarAdapters
import CursorBarDomain
import XCTest

@MainActor
final class AppModelUsageCacheTests: XCTestCase {
    func testHydratesCardsFromDiskOnInit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("appmodel-usage-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageCardSnapshotStore(applicationSupportRoot: root)
        let snapshot = Self.cardSnapshot(seatID: .seat1)
        store.write([.seat1: snapshot])
        let model = AppModel(
            keychain: CacheTestSeatStore(records: []),
            cardSnapshotStore: store,
            chartSnapshotStore: UsageChartSnapshotStore(applicationSupportRoot: root),
            userLabelStore: SeatUserLabelStore(applicationSupportRoot: root),
            publicRosterStore: PublicRosterStore(applicationSupportRoot: root),
            autostart: false
        )
        XCTAssertEqual(model.usageBySeat[.seat1], snapshot)
    }

    func testApplyRefreshPersistsCards() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("appmodel-usage-persist-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageCardSnapshotStore(applicationSupportRoot: root)
        let model = AppModel(
            keychain: CacheTestSeatStore(records: []),
            cardSnapshotStore: store,
            chartSnapshotStore: UsageChartSnapshotStore(applicationSupportRoot: root),
            userLabelStore: SeatUserLabelStore(applicationSupportRoot: root),
            publicRosterStore: PublicRosterStore(applicationSupportRoot: root),
            autostart: false
        )
        let snapshot = Self.cardSnapshot(seatID: .seat2)
        model.applyUsageRefreshReport(
            UsageRefreshReport(
                outcomes: [.seat2: .refreshed(snapshot)],
                bindingEpochs: [.seat2: 0]
            )
        )
        XCTAssertEqual(store.load()[.seat2], snapshot)
    }

    func testHydratesChartFromDiskOnInit() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("appmodel-chart-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chartStore = UsageChartSnapshotStore(applicationSupportRoot: root)
        let series = UsageSeries(
            scope: .allAccounts,
            rangeStart: UsageDayKey(year: 2026, month: 8, day: 1),
            rangeEnd: UsageDayKey(year: 2026, month: 8, day: 1),
            points: [
                UsagePoint(
                    day: UsageDayKey(year: 2026, month: 8, day: 1),
                    tokens: 9,
                    spendCents: nil,
                    coverage: .complete
                ),
            ],
            coverage: PartialCoverage(includedAccountCount: 1, requestedAccountCount: 1),
            costAvailable: false
        )
        chartStore.write(
            UsageChartSnapshot(
                series: series,
                tokenSummary: nil,
                insights: nil,
                scope: .allAccounts,
                range: .month(YearMonth(year: 2026, month: 8)),
                metric: .tokens,
                settledAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        let model = AppModel(
            keychain: CacheTestSeatStore(records: []),
            cardSnapshotStore: UsageCardSnapshotStore(applicationSupportRoot: root),
            chartSnapshotStore: chartStore,
            userLabelStore: SeatUserLabelStore(applicationSupportRoot: root),
            publicRosterStore: PublicRosterStore(applicationSupportRoot: root),
            autostart: false
        )
        XCTAssertEqual(model.usageSeries.series, series)
        XCTAssertEqual(model.usageSeries.phase, .settled)
    }

    func testSignedInCredentialsCacheKeychainReads() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("appmodel-cred-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CacheTestSeatStore(records: [])
        let model = AppModel(
            keychain: store,
            cardSnapshotStore: UsageCardSnapshotStore(applicationSupportRoot: root),
            chartSnapshotStore: UsageChartSnapshotStore(applicationSupportRoot: root),
            userLabelStore: SeatUserLabelStore(applicationSupportRoot: root),
            publicRosterStore: PublicRosterStore(applicationSupportRoot: root),
            autostart: false
        )
        _ = model.signedInCredentialsForTests()
        let afterFirst = store.loadAllCount
        _ = model.signedInCredentialsForTests()
        XCTAssertEqual(store.loadAllCount, afterFirst)
        model.reloadShellFromKeychain()
        let afterReload = store.loadAllCount
        _ = model.signedInCredentialsForTests()
        XCTAssertEqual(store.loadAllCount, afterReload + 1)
    }

    private static func cardSnapshot(seatID: SeatID) -> SeatUsageSnapshot {
        SeatUsageSnapshot(
            seatID: seatID,
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
    }
}

private final class CacheTestSeatStore: SeatCredentialStore, @unchecked Sendable {
    private var records: [SeatID: StoredSeatRecord]
    private(set) var loadAllCount = 0

    init(records: [StoredSeatRecord]) {
        var map: [SeatID: StoredSeatRecord] = [:]
        for record in records {
            map[record.seatID] = record
        }
        self.records = map
    }

    func loadAll() throws -> [StoredSeatRecord] {
        loadAllCount += 1
        return records.values.sorted { $0.seatID < $1.seatID }
    }

    func load(seatID: SeatID) throws -> StoredSeatRecord? {
        records[seatID]
    }

    func save(_ record: StoredSeatRecord) throws {
        records[record.seatID] = record
    }

    func delete(seatID: SeatID) throws {
        records[seatID] = nil
    }
}
