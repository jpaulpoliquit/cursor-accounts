@testable import CursorBar
import CursorBarAdapters
import CursorBarDomain
import XCTest

@MainActor
final class OpenRefreshHooksTests: XCTestCase {
    func testAppModelExposesOpenRefreshHooks() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appModel = try String(contentsOf: root.appendingPathComponent("Sources/App/AppModel.swift"))
        let openRefresh = try String(contentsOf: root.appendingPathComponent("Sources/App/AppModel+OpenRefresh.swift"))
        let lifecycle = try String(contentsOf: root.appendingPathComponent("Sources/App/AppModel+AccountLifecycle.swift"))
        let menuRoot = try String(contentsOf: root.appendingPathComponent("Sources/App/MenuBarRoot.swift"))
        let dashboard = try String(contentsOf: root.appendingPathComponent("Sources/App/Dashboard/DashboardView.swift"))
        let app = try String(contentsOf: root.appendingPathComponent("Sources/App/CursorBarApp.swift"))
        let refresh = try String(contentsOf: root.appendingPathComponent("Sources/App/Usage/UsageSeriesCoordinator+Refresh.swift"))
        XCTAssertTrue(openRefresh.contains("func refreshOnMenuOpen()"))
        XCTAssertTrue(openRefresh.contains("func refreshOnDashboardOpen()"))
        XCTAssertTrue(openRefresh.contains("hydrateSeatProfiles()"))
        XCTAssertTrue(openRefresh.contains("prefetchSeatPictures()"))
        XCTAssertTrue(openRefresh.contains("func noteDashboardClosed()"))
        XCTAssertTrue(openRefresh.contains("func refreshCardsIfPolicyAllows(trigger:"))
        XCTAssertTrue(openRefresh.contains("refreshAllIfIdle()"))
        XCTAssertTrue(appModel.contains("refreshCardsIfPolicyAllows(trigger: .bootstrap)"))
        XCTAssertTrue(lifecycle.contains("refreshCardsIfPolicyAllows(trigger: .bootstrap)"))
        XCTAssertFalse(appModel.contains("refreshAllIfIdle(trigger: .bootstrap)"))
        XCTAssertFalse(lifecycle.contains("refreshAllIfIdle(trigger: .bootstrap)"))
        XCTAssertFalse(appModel.contains("warmAllConnectedSeats()"))
        XCTAssertFalse(openRefresh.contains("warmAllConnectedSeats()"))
        XCTAssertFalse(lifecycle.contains("warmAllConnectedSeats()"))
        XCTAssertTrue(menuRoot.contains("refreshOnMenuOpen()"))
        XCTAssertTrue(menuRoot.contains("MenuBarMenuOpenBridge"))
        XCTAssertTrue(dashboard.contains("refreshOnDashboardOpen()"))
        XCTAssertTrue(dashboard.contains("noteDashboardClosed()"))
        XCTAssertTrue(dashboard.contains("onDisappear"))
        XCTAssertTrue(dashboard.contains("dashboardVisible"))
        XCTAssertTrue(menuRoot.contains("model.refreshOnDashboardOpen()"))
        XCTAssertFalse(app.contains("raiseExistingOrNextRunLoop"))
        XCTAssertFalse(refresh.contains("onProgress:"))
    }

    func testDashboardUsageViewsNeverShowUpdatingCopy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chart = try String(contentsOf: root.appendingPathComponent("Sources/App/Dashboard/UsageChartView.swift"))
        let insights = try String(contentsOf: root.appendingPathComponent("Sources/App/Dashboard/UsageInsightsView.swift"))
        XCTAssertFalse(chart.contains("Updating…"))
        XCTAssertFalse(chart.contains("Updating usage"))
        XCTAssertFalse(insights.contains("Updating…"))
    }

    func testOpenRefreshSchedulerDebouncesAndMergesSurfaces() async {
        let scheduler = OpenRefreshScheduler(debounceNanoseconds: 50_000_000)
        var fired: Set<OpenRefreshSurface> = []
        scheduler.schedule(.menuBar) { fired = $0 }
        scheduler.schedule(.dashboard) { fired = $0 }
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(fired, [.menuBar, .dashboard])
    }

    func testRefreshAllIfIdleJoinsInFlightPass() async throws {
        let gate = RefreshHangGate()
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let refresher = SeatUsageRefresher(client: DashboardClient { _ in
            await gate.waitUntilReleased()
            throw URLError(.cancelled)
        })
        let coordinator = UsageRefreshCoordinator(refresher: refresher)
        coordinator.configure(
            loadCredentials: {
                [SeatUsageRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            applyReport: { _ in },
            onChange: {}
        )
        coordinator.refreshAllIfIdle()
        for _ in 0..<50 {
            if coordinator.isRefreshing { break }
            await Task.yield()
        }
        XCTAssertTrue(coordinator.isRefreshing)
        coordinator.refreshAllIfIdle()
        XCTAssertTrue(coordinator.isRefreshing)
        await gate.release()
    }

    func testRefreshAllIfIdleSkipsFreshSnapshots() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        var fetches = 0
        let refresher = SeatUsageRefresher(client: DashboardClient { _ in
            fetches += 1
            throw URLError(.cancelled)
        })
        let coordinator = UsageRefreshCoordinator(refresher: refresher)
        coordinator.configure(
            loadCredentials: {
                [SeatUsageRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            applyReport: { _ in },
            onChange: {},
            fetchedAt: { _ in Date() }
        )
        coordinator.refreshAllIfIdle()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fetches, 0)
        XCTAssertFalse(coordinator.isRefreshing)
    }

    func testCancelForSeatLeavesRefreshAllRunning() async throws {
        let gate = RefreshHangGate()
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let refresher = SeatUsageRefresher(client: DashboardClient { _ in
            await gate.waitUntilReleased()
            throw URLError(.cancelled)
        })
        let coordinator = UsageRefreshCoordinator(refresher: refresher)
        coordinator.configure(
            loadCredentials: {
                [
                    SeatUsageRefresher.SeatCredential(seatID: .seat1, access: token),
                    SeatUsageRefresher.SeatCredential(seatID: .seat2, access: token),
                ]
            },
            applyReport: { _ in },
            onChange: {}
        )
        coordinator.refreshAllIfIdle()
        for _ in 0..<50 {
            if coordinator.isRefreshing { break }
            await Task.yield()
        }
        XCTAssertTrue(coordinator.isRefreshing)
        coordinator.cancelForSeat(.seat2)
        coordinator.refresh(seatID: .seat2)
        guard case .refreshing(.all) = coordinator.phase else {
            return XCTFail("refresh-all must keep running, phase=\(coordinator.phase)")
        }
        await gate.release()
    }

    func testCancelForSeatAbortsThatSeatRefresh() async throws {
        let gate = RefreshHangGate()
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let refresher = SeatUsageRefresher(client: DashboardClient { _ in
            await gate.waitUntilReleased()
            throw URLError(.cancelled)
        })
        let coordinator = UsageRefreshCoordinator(refresher: refresher)
        coordinator.configure(
            loadCredentials: {
                [SeatUsageRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            applyReport: { _ in },
            onChange: {}
        )
        coordinator.refresh(seatID: .seat1)
        for _ in 0..<50 {
            if coordinator.isRefreshing { break }
            await Task.yield()
        }
        XCTAssertTrue(coordinator.isRefreshing)
        coordinator.cancelForSeat(.seat1)
        XCTAssertFalse(coordinator.isRefreshing)
        await gate.release()
    }

    func testDiscardedRefreshAllReturnsToIdle() async throws {
        let gate = RefreshHangGate()
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let refresher = SeatUsageRefresher(client: DashboardClient { _ in
            await gate.waitUntilReleased()
            throw URLError(.cancelled)
        })
        let coordinator = UsageRefreshCoordinator(refresher: refresher)
        coordinator.configure(
            loadCredentials: {
                [SeatUsageRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            applyReport: { _ in },
            onChange: {}
        )
        coordinator.refreshAllIfIdle()
        for _ in 0..<50 {
            if coordinator.isRefreshing { break }
            await Task.yield()
        }
        XCTAssertTrue(coordinator.isRefreshing)
        await refresher.invalidateBinding(seatID: .seat1, epoch: 1)
        await gate.release()
        for _ in 0..<50 {
            if !coordinator.isRefreshing { break }
            await Task.yield()
        }
        XCTAssertFalse(coordinator.isRefreshing)
    }
}

private actor RefreshHangGate {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilReleased() async {
        if released { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
