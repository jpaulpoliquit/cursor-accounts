@testable import CursorBar
import CursorBarAdapters
import CursorBarDomain
import XCTest

@MainActor
final class UsageRefreshReportApplyTests: XCTestCase {
    func testFailedUsageRefreshSurfacesMessageOnSeat() throws {
        let record = StoredSeatRecord(
            seatID: .seat1,
            identity: .subject("usage-user"),
            access: try XCTUnwrap(AccessToken("access.usage.jwt")),
            refresh: try XCTUnwrap(RefreshToken("refresh.usage")),
            email: Email("usage@example.com"),
            displayName: DisplayName("usage"),
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
            membershipType: "ultra",
            subscriptionStatus: "active"
        )
        let store = ReportApplySeatStore(records: [record])
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-apply-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(
            keychain: store,
            cardSnapshotStore: UsageCardSnapshotStore(applicationSupportRoot: cacheRoot),
            chartSnapshotStore: UsageChartSnapshotStore(applicationSupportRoot: cacheRoot),
            userLabelStore: SeatUserLabelStore(applicationSupportRoot: cacheRoot),
            publicRosterStore: PublicRosterStore(applicationSupportRoot: cacheRoot),
            autostart: false
        )
        model.reloadShellFromKeychain()
        model.applyUsageRefreshReport(
            UsageRefreshReport(
                outcomes: [.seat1: .failed(message: "Denied")],
                bindingEpochs: [.seat1: 0]
            )
        )
        model.reproject()
        XCTAssertEqual(model.presentation.seats.first?.authDetail, "Denied")
    }
}

private final class ReportApplySeatStore: SeatCredentialStore, @unchecked Sendable {
    private var records: [SeatID: StoredSeatRecord]

    init(records: [StoredSeatRecord]) {
        var map: [SeatID: StoredSeatRecord] = [:]
        for record in records {
            map[record.seatID] = record
        }
        self.records = map
    }

    func loadAll() throws -> [StoredSeatRecord] {
        records.values.sorted { $0.seatID < $1.seatID }
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
