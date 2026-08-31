import CursorBarAdapters
import CursorBarDomain
import XCTest

/// Phase 4 presentation evidence without Keychain prompts (SecurityAgent blocks XCTest).
final class Phase4RuntimePresentationTests: XCTestCase {
    func testMaskedProjectionNeverShowsEmail() {
        let seat = SeatSnapshot(
            seatID: .seat1,
            auth: .signedIn,
            email: Email("ksj8718739bndrfps21e@gmail.com"),
            displayName: DisplayName("john 5"),
            plan: PlanInfo(name: "ultra"),
            usage: PeriodUsage(
                autoPercentUsed: PercentUsed(unchecked: 68),
                apiPercentUsed: PercentUsed(unchecked: 100),
                totalPercentUsed: PercentUsed(unchecked: 84)
            ),
            onDemand: OnDemandState(mode: .fixed(PositiveDollars(190)!))
        )
        let masked = SeatPresentationProjector.project(
            aggregate: AggregateSnapshot(seats: [seat]),
            usageBySeat: [:],
            identityPolicy: .maskEmail,
            focusedSeatID: .seat1,
            loginPhases: [:],
            bootstrapPhase: .settled(.kept(.seat1)),
            usageRefreshPhase: .idle,
            setHardLimitPhase: .idle
        )
        let focused = masked.focusedSeat!
        XCTAssertEqual(focused.label.text, "john 5")
        XCTAssertNil(focused.revealedEmail)
        XCTAssertFalse(focused.accessibilityLabel.contains("@"))
        XCTAssertFalse(focused.rootMenuTitle.contains("@"))
        XCTAssertEqual(focused.onDemand?.modeLabel, "Fixed $190")
        XCTAssertFalse(String(describing: masked).contains("Included usage"))
    }

    func testCachedScopedProfileDisplayNameImports() throws {
        let source = CursorDesktopSessionSource()
        guard let imported = try source.load() else {
            throw XCTSkip("No active Cursor desktop session")
        }
        guard let displayName = imported.displayName?.value, !displayName.isEmpty else {
            throw XCTSkip("Desktop session has no cached display name")
        }
        XCTAssertFalse(displayName.isEmpty)
        let label = AccountLabelResolver.resolve(
            policy: .maskEmail,
            source: .init(
                seatID: .seat1,
                email: imported.email,
                displayName: imported.displayName
            )
        )
        XCTAssertEqual(label.text, displayName)
        XCTAssertFalse(label.text.contains("@"))
    }

    func testLiveReadProjectsSeparatePoolsAndOnDemand() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PHASE4_LIVE_READ"] == "1"
                || FileManager.default.fileExists(atPath: "/tmp/cursorbar-phase4-live-read"),
            "Enable via PHASE4_LIVE_READ=1 or /tmp/cursorbar-phase4-live-read"
        )
        let source = CursorDesktopSessionSource()
        let imported = try XCTUnwrap(try source.load())
        let ready = try XCTUnwrap(ConnectReadyAccessToken(imported.access))
        let client = DashboardClient()
        let plan = try await client.getPlanInfo(access: ready)
        let period = try await client.getCurrentPeriodUsage(access: ready)
        let hardLimit = try await client.getHardLimit(access: ready)
        let credits = try await client.getCreditGrantsBalance(access: ready)
        let policy = try await client.getUsageLimitPolicyStatus(access: ready)
        let snap = SeatUsageSnapshot(
            seatID: .seat1,
            plan: plan,
            period: period,
            hardLimit: hardLimit,
            credits: credits,
            policy: policy,
            fetchedAt: Date()
        )
        let presentation = SeatPresentationProjector.project(
            aggregate: AggregateSnapshot(seats: [
                SeatSnapshot(
                    seatID: .seat1,
                    auth: .signedIn,
                    email: imported.email,
                    displayName: imported.displayName,
                    plan: plan,
                    usage: period.usage,
                    onDemand: snap.onDemand
                )
            ]),
            usageBySeat: [.seat1: snap],
            identityPolicy: .maskEmail,
            focusedSeatID: .seat1,
            loginPhases: [:],
            bootstrapPhase: .settled(.kept(.seat1)),
            usageRefreshPhase: .idle,
            setHardLimitPhase: .idle
        )
        let seat = try XCTUnwrap(presentation.focusedSeat)
        let auto = try XCTUnwrap(seat.autoPercent)
        let api = try XCTUnwrap(seat.apiPercent)
        print(
            "PHASE4_LIVE auto=\(auto.percent) api=\(api.percent) onDemand=\(seat.onDemand?.menuTitle ?? "nil") label=\(seat.label.text) plan=\(seat.planName ?? "nil")"
        )
        XCTAssertFalse(seat.label.text.contains("@"))
        XCTAssertNil(seat.revealedEmail)
        XCTAssertNotNil(seat.onDemand)
    }
}
