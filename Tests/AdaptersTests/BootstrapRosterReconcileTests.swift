import CursorBarAdapters
import CursorBarDomain
import XCTest

final class BootstrapRosterReconcileTests: XCTestCase {
    func testShellSnapshotQuarantinesSubjectOnlySeat2AndKeepsSeat1() throws {
        let store = UncheckedMemorySeatStore()
        let seat1 = StoredSeatRecord(
            seatID: .seat1,
            identity: .subject("real-sub"),
            access: try XCTUnwrap(AccessToken("access-1")),
            refresh: try XCTUnwrap(RefreshToken("refresh-1")),
            email: Email("user@example.com"),
            displayName: DisplayName("john 5"),
            expiresAt: Date(timeIntervalSince1970: 9_999_999),
            membershipType: "ultra",
            subscriptionStatus: "active"
        )
        let seat2 = StoredSeatRecord(
            seatID: .seat2,
            identity: .subject("ghost-sub"),
            access: try XCTUnwrap(AccessToken("access-2")),
            refresh: try XCTUnwrap(RefreshToken("refresh-2")),
            email: nil,
            displayName: nil,
            expiresAt: Date(timeIntervalSince1970: 9_999_999),
            membershipType: nil,
            subscriptionStatus: nil
        )
        try store.save(seat1)
        try store.save(seat2)

        let orchestrator = BootstrapOrchestrator(
            sessionSource: CursorDesktopSessionSource(
                processArgumentsProvider: { [] },
                homeDirectory: URL(fileURLWithPath: "/tmp/cursorbar-no-desktop-\(UUID().uuidString)")
            ),
            keychain: store,
            probe: DashboardSessionProbe(client: DashboardClient { _ in
                throw URLError(.notConnectedToInternet)
            })
        )
        let shell = try orchestrator.shellSnapshot()
        XCTAssertEqual(shell.signedInCount, 1)
        XCTAssertEqual(shell.seats.first(where: { $0.seatID == .seat1 })?.auth, .signedIn)
        XCTAssertNil(shell.seats.first(where: { $0.seatID == .seat2 }))
        XCTAssertNil(try store.load(seatID: .seat2))
        XCTAssertNotNil(try store.load(seatID: .seat1))
    }

    func testShellSnapshotThrowsWhenKeychainUnreadable() {
        let orchestrator = BootstrapOrchestrator(
            sessionSource: CursorDesktopSessionSource(
                processArgumentsProvider: { [] },
                homeDirectory: URL(fileURLWithPath: "/tmp/cursorbar-no-desktop-\(UUID().uuidString)")
            ),
            keychain: ThrowingSeatStore(),
            probe: DashboardSessionProbe(client: DashboardClient { _ in
                throw URLError(.notConnectedToInternet)
            })
        )
        XCTAssertThrowsError(try orchestrator.shellSnapshot())
    }
}

private struct ThrowingSeatStore: SeatCredentialStore {
    func loadAll() throws -> [StoredSeatRecord] {
        throw SeatKeychainStore.StoreError.accessDenied(-50)
    }

    func load(seatID: SeatID) throws -> StoredSeatRecord? {
        throw SeatKeychainStore.StoreError.accessDenied(-50)
    }

    func save(_ record: StoredSeatRecord) throws {}
    func delete(seatID: SeatID) throws {}
}
