import CursorBarAdapters
import CursorBarDomain
import XCTest

/// Opt-in multi-seat All Time bound probe. Redacted output only.
final class LiveAllTimeBoundsVerifyTests: XCTestCase {
    func testAllAccountsAllTimeIncludesOlderSeatJanuaryWindow() async throws {
        let enabled =
            ProcessInfo.processInfo.environment["LIVE_DASHBOARD_VERIFY"] == "1"
            || ProcessInfo.processInfo.environment["CURSORBAR_LIVE"] == "1"
            || FileManager.default.fileExists(atPath: "/tmp/cursorbar-live-dashboard-verify")
            || FileManager.default.fileExists(atPath: NSTemporaryDirectory() + "cursorbar-live-dashboard-verify")
        guard enabled else {
            throw XCTSkip("Enable via LIVE_DASHBOARD_VERIFY=1 or /tmp/cursorbar-live-dashboard-verify")
        }

        // Explicit owned-service read for opt-in live probes only.
        let store = SeatKeychainStore(serviceName: KeychainServicePolicy.ownedServiceName)
        let roster = (try? store.loadAll()) ?? []
        let credentials: [SeatUsageRefresher.SeatCredential] = roster.compactMap { record in
            guard let access = ConnectReadyAccessToken(record.access) else { return nil }
            return .init(seatID: record.seatID, access: access)
        }
        guard credentials.count >= 2 else {
            throw XCTSkip("Need at least two keychain seats for multi-seat All Time probe")
        }

        guard let bounds = await AllTimeBoundLookup.resolve(credentials: credentials) else {
            return XCTFail("AllTimeBoundLookup returned nil with connected seats")
        }
        guard let window = bounds.chartWindow(for: .allAccounts) else {
            return XCTFail("All Accounts chart window missing despite resolved starts")
        }
        print("LIVE all_time_start=\(window.start.isoDate)")
        print("LIVE all_time_end=\(window.end.isoDate)")
        print("LIVE all_time_resolved_seats=\(bounds.resolvedSeatCount)")
        print("LIVE all_time_requested_seats=\(bounds.requestedSeatCount)")
        print("LIVE all_time_partial_bound=\(bounds.isPartial)")

        let january = UsageDayKey(year: 2026, month: 1, day: 15)
        XCTAssertLessThanOrEqual(window.start, UsageDayKey(year: 2026, month: 1, day: 1))
        XCTAssertGreaterThanOrEqual(window.end, january)

        // Pick an older resolved seat (start before 2026-07) and confirm Jan 2026 daily rows exist.
        let older = bounds.resolvedStarts
            .filter { $0.value < UsageDayKey(year: 2026, month: 7, day: 1) }
            .min(by: { $0.value < $1.value })
        guard let olderSeat = older?.key else {
            throw XCTSkip("No resolved seat starting before 2026-07 in this keychain snapshot")
        }
        print("LIVE older_seat=\(olderSeat.rawValue)")
        print("LIVE older_seat_start=\(bounds.start(for: olderSeat)?.isoDate ?? "nil")")

        guard let credential = credentials.first(where: { $0.seatID == olderSeat }) else {
            return XCTFail("missing credential for older seat")
        }
        let month = YearMonth(year: 2026, month: 1)
        let interval = month.utcHalfOpenIntervalMs(timeZone: TimeZone(secondsFromGMT: 0)!)
        let rows = try await DashboardClient().getDailySpendByCategory(
            access: credential.access,
            periodStartMs: interval.startMs,
            periodEndMs: interval.endExclusiveMs
        )
        let tokenSum = rows.reduce(Int64(0)) { $0 + $1.totalTokens }
        print("LIVE jan2026_row_count=\(rows.count)")
        print("LIVE jan2026_token_sum=\(tokenSum)")
        print("LIVE jan2026_included_in_all_accounts_window=\(window.start <= UsageDayKey(year: 2026, month: 1, day: 1))")
        XCTAssertTrue(
            window.start <= UsageDayKey(year: 2026, month: 1, day: 1),
            "All Accounts All Time must start at/before Jan 2026 when an older seat exists"
        )
    }
}
