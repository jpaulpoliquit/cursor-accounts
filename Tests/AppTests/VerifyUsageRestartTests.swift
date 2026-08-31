@testable import CursorBar
import CursorBarAdapters
import CursorBarDomain
import XCTest

@MainActor
final class VerifyUsageRestartTests: XCTestCase {
    func testSeedRoundTripsThroughStoresAndHydratesAppModel() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-usage-seed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        VerifyUsageCacheSeed.write(to: root)

        let cards = UsageCardSnapshotStore(applicationSupportRoot: root).load()
        XCTAssertEqual(cards[.seat1]?.plan.name, VerifyUsageCacheSeed.planName)
        XCTAssertEqual(cards[.seat1]?.period.usage.autoPercentUsed.percent, VerifyUsageCacheSeed.autoPercent)

        let chart = UsageChartSnapshotStore(applicationSupportRoot: root).load()
        XCTAssertEqual(
            chart?.series?.points.reduce(Int64(0)) { $0 + $1.tokens },
            VerifyUsageCacheSeed.tokenSum
        )

        let model = AppModel(
            keychain: RestartTestSeatStore(),
            cardSnapshotStore: UsageCardSnapshotStore(applicationSupportRoot: root),
            chartSnapshotStore: UsageChartSnapshotStore(applicationSupportRoot: root),
            autostart: false
        )
        XCTAssertEqual(model.usageBySeat[.seat1]?.plan.name, VerifyUsageCacheSeed.planName)
        XCTAssertEqual(model.usageSeries.series?.points.first?.tokens, VerifyUsageCacheSeed.tokenSum)
        XCTAssertEqual(model.usageSeries.phase, .settled)
        XCTAssertFalse(model.dashboardVisible)
        if case .idle = model.usageSeries.historyWarmPhase {
        } else {
            XCTFail("hidden hydrate must not start history warm")
        }
    }

    func testDumpSourceIncludesImmediateLastKnownFields() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dump = try String(
            contentsOf: root.appendingPathComponent("Sources/App/VerifyPresentationDump.swift")
        )
        XCTAssertTrue(dump.contains("dumpIfRequested(model: model)"))
        XCTAssertTrue(dump.contains("dashboard_visible="))
        XCTAssertTrue(dump.contains("history_warm="))
        XCTAssertTrue(dump.contains("usage_cards_count="))
        XCTAssertTrue(dump.contains("usage_card_plans="))
        XCTAssertTrue(dump.contains("2.0"))
    }
}

private final class RestartTestSeatStore: SeatCredentialStore, @unchecked Sendable {
    func loadAll() throws -> [StoredSeatRecord] { [] }
    func load(seatID: SeatID) throws -> StoredSeatRecord? { nil }
    func save(_ record: StoredSeatRecord) throws {}
    func delete(seatID: SeatID) throws {}
}
