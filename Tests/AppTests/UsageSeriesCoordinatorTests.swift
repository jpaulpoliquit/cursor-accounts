@testable import CursorBar
import CursorBarAdapters
import CursorBarDomain
import XCTest

@MainActor
final class UsageSeriesCoordinatorTests: XCTestCase {
    func testOlderCompletionCannotOverwriteNewerSeries() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let gate = CoordinatorStallGate()
        let dayMs = UsageDayKey.utcDay(containing: Date()).utcMidnightMs
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                await gate.waitIfFirst()
                let tokens = await gate.tokensForCurrentRequest()
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: tokens))
            }
            return try usageCoordOK(request, "{}")
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: {
                [
                    (.allAccounts, "All Accounts"),
                    (.account(.seat1), "john 5"),
                ]
            },
            onChange: {}
        )

        await gate.armFirstHold()
        coordinator.refresh()
        await gate.waitUntilFirstHeld()
        await gate.setFastTokens(321)
        coordinator.refresh()
        await usageCoordWait(coordinator) {
            $0.phase == .settled && $0.series?.points.contains(where: { $0.tokens == 321 }) == true
        }
        XCTAssertEqual(coordinator.series?.points.first(where: { $0.tokens == 321 })?.tokens, 321)
        await gate.releaseFirst()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(coordinator.series?.points.first(where: { $0.tokens == 321 })?.tokens, 321)
    }

    func testCancelledRefreshKeepsLastKnownSeries() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let dayMs = UsageDayKey.utcDay(containing: Date()).utcMidnightMs
        nonisolated(unsafe) var failNext = false
        let client = DashboardClient { request in
            if failNext {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 88))
            }
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 88))
            }
            return try usageCoordOK(request, "{}")
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        coordinator.refresh()
        await usageCoordWait(coordinator) { $0.phase == .settled && $0.series != nil }
        XCTAssertEqual(coordinator.series?.points.first(where: { $0.tokens == 88 })?.tokens, 88)
        XCTAssertEqual(coordinator.tokenSummary?.totals.total, 88)

        failNext = true
        coordinator.refresh()
        await usageCoordWait(coordinator) { $0.phase == .settled }
        XCTAssertEqual(coordinator.series?.points.first(where: { $0.tokens == 88 })?.tokens, 88)
        XCTAssertEqual(coordinator.tokenSummary?.totals.total, 88)
    }

    func testScopeLabelsUnderMaskHaveNoAtOrLocalPart() {
        let coordinator = UsageSeriesCoordinator()
        coordinator.configure(
            loadCredentials: { [] },
            connectedScopes: {
                let email = Email("hidden.user@example.com")!
                let masked = AccountLabelResolver.resolve(
                    policy: .maskEmail,
                    source: .init(seatID: .seat1, email: email, displayName: DisplayName("john 5"))
                )
                return [
                    (.allAccounts, "All Accounts"),
                    (.account(.seat1), masked.text),
                ]
            },
            onChange: {}
        )
        let labels = coordinator.scopeOptions.map(\.1)
        XCTAssertTrue(labels.contains("All Accounts"))
        XCTAssertTrue(labels.contains("john 5"))
        for label in labels {
            XCTAssertFalse(label.contains("@"))
            XCTAssertFalse(label.contains("hidden.user"))
        }
    }

    func testCostMetricHiddenAndTokensDefaultWhenSpendAbsent() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let dayMs = UsageDayKey.utcDay(containing: Date()).utcMidnightMs
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 5))
            }
            return try usageCoordOK(request, "{}")
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        XCTAssertEqual(coordinator.metric, .tokens)
        coordinator.refresh()
        await usageCoordWait(coordinator) { $0.phase == .settled && $0.series != nil }
        XCTAssertFalse(coordinator.costAvailable)
        coordinator.selectMetric(.costCents)
        XCTAssertEqual(coordinator.resolvedMetric, .tokens)
        XCTAssertEqual(coordinator.metric, .tokens)
    }

    func testAccessibilityDescriptorNamesDailyTokensRangeScopePartial() async throws {
        let day = UsageDayKey.utcDay(containing: Date())
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let seat2 = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seat2.sig"))
        let client = DashboardClient { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if auth.contains("seat2") {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: day.utcMidnightMs, tokens: 3))
            }
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 3))
            }
            return try usageCoordOK(request, "{}")
        }
        let live = usageCoordMake(client: client)
        live.configure(
            loadCredentials: {
                [
                    .init(seatID: .seat1, access: token),
                    .init(seatID: .seat2, access: seat2),
                ]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        live.refresh()
        await usageCoordWait(live) {
            $0.phase == .settled && $0.series?.coverage.caption == "1 of 2 accounts"
        }
        let text = live.accessibilityDescriptor
        XCTAssertTrue(text.contains("Daily tokens"), text)
        XCTAssertTrue(text.contains("All Accounts"), text)
        XCTAssertTrue(text.contains(live.series?.rangeStart.isoDate ?? ""), text)
        XCTAssertTrue(text.contains("1 of 2 accounts"), text)
        XCTAssertTrue(text.contains("Usage range"), text)
        _ = day
    }

    func testDefaultRangeIsCurrentMonthAndNextDisabled() {
        let tz = TimeZone(identifier: "Asia/Taipei")!
        let coordinator = UsageSeriesCoordinator(timeZone: tz)
        guard case .month(let month) = coordinator.range else {
            return XCTFail("expected month default")
        }
        XCTAssertEqual(month, YearMonth.current(timeZone: tz))
        XCTAssertFalse(coordinator.canGoNext)
        XCTAssertTrue(coordinator.canGoPrevious)
    }

    func testScopeChangePreservesRangeAndRangeChangePreservesScope() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let dayMs = UsageDayKey.utcDay(containing: Date()).utcMidnightMs
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 4))
            }
            return try usageCoordOK(request, "{}")
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: {
                [(.allAccounts, "All Accounts"), (.account(.seat1), "john 5")]
            },
            onChange: {}
        )
        let prior = YearMonth.current().previous
        coordinator.selectRange(.month(prior))
        await usageCoordWait(coordinator) { $0.phase == .settled }
        XCTAssertEqual(coordinator.scope, .allAccounts)
        coordinator.selectScope(.account(.seat1))
        await usageCoordWait(coordinator) { $0.phase == .settled && $0.scope == .account(.seat1) }
        guard case .month(let kept) = coordinator.range else {
            return XCTFail("range should stay month")
        }
        XCTAssertEqual(kept, prior)
        coordinator.goToCurrentMonth()
        await usageCoordWait(coordinator) { $0.phase == .settled }
        XCTAssertEqual(coordinator.scope, .account(.seat1))
    }

    func testStalePriorRangeResponseDoesNotOverwriteSelectedRange() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let gate = CoordinatorStallGate()
        let dayMs = UsageDayKey.utcDay(containing: Date()).utcMidnightMs
        let client = DashboardClient { request in
            if request.url?.lastPathComponent == "GetDailySpendByCategory" {
                await gate.waitIfFirst()
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 7))
            }
            return try usageCoordOK(request, "{}")
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        let older = YearMonth.current().previous
        await gate.armFirstHold()
        coordinator.selectRange(.month(older))
        await gate.waitUntilFirstHeld()
        coordinator.goToCurrentMonth()
        await gate.releaseFirst()
        await usageCoordWait(coordinator) {
            $0.phase == .settled && $0.range == .defaultMonth()
        }
        guard case .month(let month) = coordinator.range else {
            return XCTFail("expected current month")
        }
        XCTAssertEqual(month, YearMonth.current())
    }

    func testLoadingStateRetainsLastKnownChart() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let gate = CoordinatorStallGate()
        let dayMs = UsageDayKey.utcDay(containing: Date()).utcMidnightMs
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                await gate.waitIfFirst()
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 12))
            }
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 12))
            }
            return try usageCoordOK(request, "{}")
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        await gate.armFirstHold(hold: false)
        coordinator.refresh()
        await usageCoordWait(coordinator) { $0.phase == .settled && $0.series != nil }
        XCTAssertEqual(coordinator.series?.points.first(where: { $0.tokens == 12 })?.tokens, 12)

        await gate.armFirstHold()
        coordinator.refresh()
        await gate.waitUntilFirstHeld()
        XCTAssertEqual(coordinator.phase, .refreshing)
        XCTAssertEqual(coordinator.series?.points.first(where: { $0.tokens == 12 })?.tokens, 12)
        await gate.releaseFirst()
        await usageCoordWait(coordinator) { $0.phase == .settled }
    }

    func testRemoveAccountClearsVisibleAllAccountsAndBlocksBleedBeforeRefetch() async throws {
        let tokenA = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.accountA.sig"))
        let tokenB = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.accountB.sig"))
        let dayMs = UsageDayKey.utcDay(containing: Date()).utcMidnightMs
        nonisolated(unsafe) var allowB = false
        let client = DashboardClient { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if auth.contains("accountA") {
                let method = request.url?.lastPathComponent ?? ""
                if method == "GetDailySpendByCategory" {
                    return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 111))
                }
                if method == "GetAggregatedUsageEvents" {
                    return try usageCoordOK(request, usageCoordAggregateJSON(input: 111))
                }
                return try usageCoordOK(request, #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#)
            }
            if !allowB {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 222))
            }
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 222))
            }
            return try usageCoordOK(request, #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#)
        }
        nonisolated(unsafe) var credentials = [
            UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: tokenA),
        ]
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: { credentials },
            connectedScopes: {
                var scopes: [(UsageScope, String)] = [(.allAccounts, "All Accounts")]
                if credentials.contains(where: { $0.seatID == .seat1 }) {
                    scopes.append((.account(.seat1), "account"))
                }
                return scopes
            },
            onChange: {}
        )
        coordinator.refresh()
        await usageCoordWait(coordinator) {
            $0.phase == .settled && $0.series?.points.contains(where: { $0.tokens == 111 }) == true
        }
        XCTAssertEqual(coordinator.series?.points.first(where: { $0.tokens == 111 })?.tokens, 111)

        credentials = []
        await coordinator.purgeAccount(for: .seat1, bindingEpoch: 1)
        XCTAssertNil(coordinator.series)
        XCTAssertNil(coordinator.tokenSummary)
        XCTAssertNil(coordinator.insights)

        credentials = [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: tokenB)]
        // Before B's fetch is allowed, no A residue may reappear.
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertFalse(coordinator.series?.points.contains(where: { $0.tokens == 111 }) == true)

        allowB = true
        coordinator.refresh()
        await usageCoordWait(coordinator) {
            $0.phase == .settled && $0.series?.points.contains(where: { $0.tokens == 222 }) == true
        }
        XCTAssertFalse(coordinator.series?.points.contains(where: { $0.tokens == 111 }) == true)
        XCTAssertEqual(coordinator.series?.points.first(where: { $0.tokens == 222 })?.tokens, 222)
    }

    func testRefreshIfIdleAfterPurgeDoesNotSkipEmptyChart() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.purge-idle.sig"))
        let dayMs = UsageDayKey.utcDay(containing: Date()).utcMidnightMs
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 40))
            }
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 40))
            }
            return try usageCoordOK(request, #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#)
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        coordinator.refresh()
        await usageCoordWait(coordinator) { $0.phase == .settled && $0.series != nil }
        await coordinator.purgeAccount(for: .seat1, bindingEpoch: 1)
        XCTAssertNil(coordinator.series)
        XCTAssertNil(coordinator.lastSettledAt)
        coordinator.refreshIfIdle()
        await usageCoordWait(coordinator) { $0.phase == .settled && $0.series != nil }
        XCTAssertNotNil(coordinator.series)
    }

    func testMonthRefreshDoesNotResolveAllTimeBounds() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.no-getme.sig"))
        let dayMs = UsageDayKey.utcDay(containing: Date()).utcMidnightMs
        nonisolated(unsafe) var resolveCount = 0
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 9))
            }
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 9))
            }
            return try usageCoordOK(request, #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#)
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {},
            resolveAllTimeBounds: {
                resolveCount += 1
                return nil
            }
        )
        coordinator.refresh()
        await usageCoordWait(coordinator) { $0.phase == .settled }
        XCTAssertEqual(resolveCount, 0)
    }

    func testSelectAllTimeResolvesBoundsWithoutPrefetch() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.all-time-click.sig"))
        let today = UsageDayKey.utcDay(containing: Date())
        let start = UsageDayKey(year: 2025, month: 2, day: 1)
        let dayMs = today.utcMidnightMs
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 3))
            }
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 3))
            }
            return try usageCoordOK(request, #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#)
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {},
            resolveAllTimeBounds: {
                AllTimeHistoryBounds(
                    endDay: today,
                    perSeat: [.seat1: .resolved(startDay: start)]
                )
            }
        )
        XCTAssertNil(coordinator.allTimeBound)
        coordinator.selectAllTime()
        await usageCoordWait(coordinator) {
            if case .allTime = $0.range { return true }
            return false
        }
        XCTAssertNotNil(coordinator.allTimeBound)
    }

    func testSelectAllTimeKeepsMonthTotalsThenGrows() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.all-time-grow.sig"))
        let tz = TimeZone(secondsFromGMT: 0)!
        let julyDay = UsageDayKey(year: 2026, month: 7, day: 10)
        let augustDay = UsageDayKey(year: 2026, month: 8, day: 10)
        let stall = AllTimeMonthStall()
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" || method == "GetAggregatedUsageEvents" {
                if usageCoordWindowContains(request, day: julyDay),
                   !usageCoordWindowContains(request, day: augustDay)
                {
                    await stall.wait()
                    if method == "GetDailySpendByCategory" {
                        return try usageCoordOK(request, usageCoordDailyJSON(dayMs: julyDay.utcMidnightMs, tokens: 500))
                    }
                    return try usageCoordOK(request, usageCoordAggregateJSON(input: 500))
                }
                if usageCoordWindowContains(request, day: augustDay),
                   !usageCoordWindowContains(request, day: julyDay)
                {
                    if method == "GetDailySpendByCategory" {
                        return try usageCoordOK(request, usageCoordDailyJSON(dayMs: augustDay.utcMidnightMs, tokens: 1_000))
                    }
                    return try usageCoordOK(request, usageCoordAggregateJSON(input: 1_000))
                }
                if method == "GetDailySpendByCategory" {
                    return try usageCoordOK(request, "{}")
                }
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 0))
            }
            return try usageCoordOK(request, #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#)
        }
        let coordinator = usageCoordMake(client: client, timeZone: tz)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.account(.seat1), "seat 1")] },
            onChange: {},
            resolveAllTimeBounds: {
                AllTimeHistoryBounds(
                    endDay: UsageDayKey(year: 2026, month: 8, day: 29),
                    perSeat: [.seat1: .resolved(startDay: UsageDayKey(year: 2026, month: 7, day: 1))]
                )
            }
        )
        coordinator.range = .month(YearMonth(year: 2026, month: 8))
        coordinator.selectScope(.account(.seat1))
        await usageCoordWait(coordinator) {
            $0.phase == .settled && $0.tokenSummary?.totals.total == 1_000
        }
        XCTAssertEqual(coordinator.tokenSummary?.totals.total, 1_000)
        coordinator.selectAllTime()
        await usageCoordWait(coordinator) {
            if case .allTime = $0.range { return $0.tokenSummary?.totals.total == 1_000 }
            return false
        }
        XCTAssertEqual(coordinator.tokenSummary?.totals.total, 1_000)
        await stall.release()
        await usageCoordWait(coordinator, timeoutMs: 4_000) {
            $0.tokenSummary?.totals.total == 1_500
        }
        XCTAssertEqual(coordinator.tokenSummary?.totals.total, 1_500)
    }

    func testAllMissingProgressKeepsPlottableSeries() {
        let coordinator = usageCoordMake(client: DashboardClient { _ in
            throw URLError(.cancelled)
        })
        let start = UsageDayKey(year: 2026, month: 8, day: 1)
        let end = UsageDayKey(year: 2026, month: 8, day: 3)
        let plottableSeat = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: [],
            rangeStart: start,
            rangeEnd: end
        )
        let plottable = UsageSeriesAggregator.aggregate(
            successful: [plottableSeat],
            requestedAccountCount: 1,
            scope: .account(.seat1),
            rangeStart: start,
            rangeEnd: end
        )
        XCTAssertTrue(plottable.hasPlottablePoints)
        XCTAssertEqual(plottable.points.reduce(0) { $0 + $1.tokens }, 0)
        let allTime = UsageRange.allTime(start: start, end: end)
        coordinator.series = plottable
        coordinator.scope = .account(.seat1)
        coordinator.range = allTime
        coordinator.generation = 1

        let missingSeat = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: [],
            rangeStart: start,
            rangeEnd: end,
            uncoveredDays: Set(UsageDayKey.days(from: start, through: end))
        )
        let missing = UsageSeriesAggregator.aggregate(
            successful: [missingSeat],
            requestedAccountCount: 1,
            scope: .account(.seat1),
            rangeStart: start,
            rangeEnd: end
        )
        XCTAssertFalse(missing.hasPlottablePoints)
        coordinator.applySeriesReport(
            UsageSeriesRefresher.Report(
                series: missing,
                outcomes: [.seat1: .refreshed(missingSeat)]
            ),
            token: 1,
            selectedRange: allTime,
            selectedScope: .account(.seat1),
            persist: false,
            force: false
        )
        XCTAssertEqual(coordinator.series, plottable)

        coordinator.applySeriesReport(
            UsageSeriesRefresher.Report(
                series: missing,
                outcomes: [.seat1: .refreshed(missingSeat)]
            ),
            token: 1,
            selectedRange: allTime,
            selectedScope: .account(.seat1),
            persist: false,
            force: true
        )
        XCTAssertEqual(coordinator.series, missing)
    }

    func testWarmAllConnectedSeatsArmsEachSeat() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.warm-all.sig"))
        nonisolated(unsafe) var fetchCount = 0
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetFilteredUsageEvents" {
                fetchCount += 1
                return try usageCoordOK(
                    request,
                    #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
                )
            }
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: 0, tokens: 0))
            }
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 0))
            }
            return try usageCoordOK(request, "{}")
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [
                    .init(seatID: .seat1, access: token),
                    .init(seatID: .seat2, access: token),
                ]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        coordinator.warmAllConnectedSeats()
        await usageCoordWait(coordinator, timeoutMs: 4000) {
            if case .settled = $0.historyWarmPhase(for: .seat1) { return true }
            return false
        }
        XCTAssertGreaterThan(fetchCount, 0)
    }

    func testWarmConnectedSeatsIfNeededSkipsSettledSeat() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.ifneeded.sig"))
        nonisolated(unsafe) var fetchCount = 0
        let client = DashboardClient { request in
            fetchCount += 1
            return try usageCoordOK(
                request,
                #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
            )
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        coordinator.warmAllConnectedSeats()
        await usageCoordWait(coordinator, timeoutMs: 4000) {
            if case .settled = $0.historyWarmPhase(for: .seat1) { return true }
            return false
        }
        let afterWarm = fetchCount
        coordinator.warmConnectedSeatsIfNeeded()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(fetchCount, afterWarm)
    }

    func testPauseBackgroundWorkCancelsWarm() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.pause.sig"))
        let gate = CoordinatorStallGate()
        let client = DashboardClient { request in
            await gate.waitIfFirst()
            return try usageCoordOK(
                request,
                #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
            )
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        await gate.armFirstHold()
        coordinator.warmHistory(for: .seat1)
        await gate.waitUntilFirstHeld()
        coordinator.pauseBackgroundWork()
        await gate.releaseFirst()
        let phase = coordinator.historyWarmPhase(for: .seat1)
        XCTAssertTrue(
            {
                if case .idle = phase { return true }
                if case .cancelled = phase { return true }
                return false
            }(),
            "pause must cancel warm, got \(phase)"
        )
    }

    func testReleaseIdleCachesDropsRawFetchCaches() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.release-idle.sig"))
        let utc = TimeZone(secondsFromGMT: 0)!
        let previous = YearMonth.current(timeZone: utc).previous
        let dayMs = previous.overlappingUTCDays(timeZone: utc).start.utcMidnightMs
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 9))
            }
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 9))
            }
            return try usageCoordOK(
                request,
                #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
            )
        }
        let coordinator = usageCoordMake(client: client, timeZone: utc)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        coordinator.selectRange(.month(previous))
        await usageCoordWait(coordinator, timeoutMs: 4000) {
            $0.phase == .settled && $0.insightsPhase == .settled
        }
        let eventsBefore = await coordinator.insightsRefresher.eventCacheEntryCount()
        let chunksBefore = await coordinator.refresher.chunkCacheEntryCount()
        let monthsBefore = await coordinator.tokenSummaryRefresher.monthCacheEntryCount()
        XCTAssertGreaterThan(eventsBefore, 0)
        XCTAssertGreaterThan(chunksBefore, 0)
        XCTAssertGreaterThan(monthsBefore, 0)
        XCTAssertNotNil(coordinator.insights)
        await coordinator.releaseIdleCaches()
        let eventsAfter = await coordinator.insightsRefresher.eventCacheEntryCount()
        let chunksAfter = await coordinator.refresher.chunkCacheEntryCount()
        let monthsAfter = await coordinator.tokenSummaryRefresher.monthCacheEntryCount()
        XCTAssertEqual(eventsAfter, 0)
        XCTAssertEqual(chunksAfter, 0)
        XCTAssertEqual(monthsAfter, 0)
        XCTAssertNotNil(coordinator.insights)
    }

    func testCancelWarmForOneSeatLeavesOtherSeatWarmRunning() async throws {
        let tokenA = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.warmA.sig"))
        let tokenB = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.warmB.sig"))
        let gate = CoordinatorStallGate()
        let client = DashboardClient { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if auth.contains("warmA") {
                await gate.waitIfFirst()
            }
            return try usageCoordOK(
                request,
                #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
            )
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [
                    .init(seatID: .seat1, access: tokenA),
                    .init(seatID: .seat2, access: tokenB),
                ]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        await gate.armFirstHold()
        coordinator.warmHistory(for: .seat1)
        coordinator.warmHistory(for: .seat2)
        await gate.waitUntilFirstHeld()
        await coordinator.purgeAccount(for: .seat1, bindingEpoch: 1)
        await gate.releaseFirst()
        await usageCoordWait(coordinator, timeoutMs: 4000) {
            if case .settled = $0.historyWarmPhase(for: .seat2) { return true }
            return false
        }
        let phase1 = coordinator.historyWarmPhase(for: .seat1)
        XCTAssertTrue(
            {
                if case .idle = phase1 { return true }
                if case .cancelled = phase1 { return true }
                return false
            }(),
            "seat1 warm must be cancelled/idle, got \(phase1)"
        )
        guard case .settled = coordinator.historyWarmPhase(for: .seat2) else {
            return XCTFail("seat2 warm must complete, got \(coordinator.historyWarmPhase(for: .seat2))")
        }
    }

    func testPurgeOtherAccountLeavesScopedChart() async throws {
        let tokenA = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.accountA.sig"))
        let tokenB = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.accountB.sig"))
        let dayMs = UsageDayKey.utcDay(containing: Date()).utcMidnightMs
        let client = DashboardClient { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            let tokens: Int64 = auth.contains("accountB") ? 222 : 111
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: tokens))
            }
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: tokens))
            }
            return try usageCoordOK(request, "{}")
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [
                    .init(seatID: .seat1, access: tokenA),
                    .init(seatID: .seat2, access: tokenB),
                ]
            },
            connectedScopes: {
                [
                    (.allAccounts, "All Accounts"),
                    (.account(.seat1), "a"),
                    (.account(.seat2), "b"),
                ]
            },
            onChange: {}
        )
        coordinator.selectScope(.account(.seat2))
        await usageCoordWait(coordinator) {
            $0.phase == .settled && $0.series?.points.contains(where: { $0.tokens == 222 }) == true
        }
        await coordinator.purgeAccount(for: .seat1, bindingEpoch: 1)
        XCTAssertEqual(coordinator.scope, .account(.seat2))
        XCTAssertEqual(coordinator.series?.points.first(where: { $0.tokens == 222 })?.tokens, 222)
    }

    func testTokenSummaryStaleGenerationIgnoredAndLastKnownRetained() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.sig"))
        let gate = CoordinatorStallGate()
        let dayMs = UsageDayKey.utcDay(containing: Date()).utcMidnightMs
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetAggregatedUsageEvents" {
                await gate.waitIfFirst()
                let input = await gate.tokensForCurrentRequest()
                return try usageCoordOK(request, usageCoordAggregateJSON(input: input))
            }
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 1))
            }
            return try usageCoordOK(request, "{}")
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )

        await gate.armFirstHold()
        coordinator.refresh()
        await gate.waitUntilFirstHeld()
        await gate.setFastTokens(321)
        coordinator.refresh()
        await usageCoordWait(coordinator) {
            $0.phase == .settled && $0.tokenSummary?.totals.total == 321
        }
        XCTAssertEqual(coordinator.tokenSummary?.totals.total, 321)
        await gate.releaseFirst()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(coordinator.tokenSummary?.totals.total, 321)

        nonisolated(unsafe) var failNext = false
        let failingClient = DashboardClient { request in
            if failNext {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 77))
            }
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 77))
            }
            return try usageCoordOK(request, "{}")
        }
        let retaining = usageCoordMake(client: failingClient)
        retaining.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        retaining.refresh()
        await usageCoordWait(retaining) { $0.tokenSummary?.totals.total == 77 }
        failNext = true
        retaining.refresh()
        await usageCoordWait(retaining) { $0.phase == .settled }
        XCTAssertEqual(retaining.tokenSummary?.totals.total, 77)
    }

    func testAllTimeDisplayStartsAtFirstUsageAcrossAccounts() async throws {
        let tokenA = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seatA.sig"))
        let tokenB = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.seatB.sig"))
        let created = UsageDayKey(year: 2026, month: 2, day: 1)
        let firstB = UsageDayKey(year: 2026, month: 5, day: 10)
        let firstA = UsageDayKey(year: 2026, month: 6, day: 1)
        let today = UsageDayKey.utcDay(containing: Date())
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if method == "GetDailySpendByCategory" {
                let usageDay = auth.contains("seatA") ? firstA : firstB
                let tokens: Int64 = auth.contains("seatA") ? 10 : 20
                if usageCoordPeriodContains(request, day: usageDay) {
                    return try usageCoordOK(
                        request,
                        usageCoordDailyJSON(dayMs: usageDay.utcMidnightMs, tokens: tokens)
                    )
                }
                return try usageCoordOK(request, #"{"dailySpend":[]}"#)
            }
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 10))
            }
            if method == "GetFilteredUsageEvents" {
                return try usageCoordOK(
                    request,
                    #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
                )
            }
            return try usageCoordOK(request, "{}")
        }
        let coordinator = usageCoordMake(client: client)
        coordinator.configure(
            loadCredentials: {
                [
                    .init(seatID: .seat1, access: tokenA),
                    .init(seatID: .seat2, access: tokenB),
                ]
            },
            connectedScopes: {
                [
                    (.allAccounts, "All Accounts"),
                    (.account(.seat1), "a"),
                    (.account(.seat2), "b"),
                ]
            },
            onChange: {}
        )
        coordinator.applyAllTimeBoundsForTests(
            AllTimeHistoryBounds(
                endDay: today,
                perSeat: [
                    .seat1: .resolved(startDay: created),
                    .seat2: .resolved(startDay: created),
                ]
            )
        )
        coordinator.selectRange(.allTime(start: created, end: today))
        await usageCoordWait(coordinator) {
            $0.phase == .settled && $0.series?.points.contains(where: { $0.tokens > 0 }) == true
        }
        let series = try XCTUnwrap(coordinator.series)
        XCTAssertEqual(series.rangeStart, firstB)
        XCTAssertEqual(series.coverage.includedAccountCount, 2)
        XCTAssertFalse(series.points.contains { $0.day < firstB })
        XCTAssertEqual(series.points.first { $0.day == firstB }?.tokens, 20)
        XCTAssertEqual(series.points.first { $0.day == firstA }?.tokens, 10)
        let seats = Set(series.points.flatMap(\.contributions).map(\.seatID))
        XCTAssertEqual(seats, [.seat1, .seat2])
    }

    func testHydratesChartFromDiskOnInit() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("coord-chart-hydrate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageChartSnapshotStore(applicationSupportRoot: root)
        let series = UsageSeries(
            scope: .allAccounts,
            rangeStart: UsageDayKey(year: 2026, month: 8, day: 1),
            rangeEnd: UsageDayKey(year: 2026, month: 8, day: 1),
            points: [
                UsagePoint(
                    day: UsageDayKey(year: 2026, month: 8, day: 1),
                    tokens: 17,
                    spendCents: nil,
                    coverage: .complete
                ),
            ],
            coverage: PartialCoverage(includedAccountCount: 1, requestedAccountCount: 1),
            costAvailable: false
        )
        store.write(
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
        let coordinator = UsageSeriesCoordinator(chartSnapshotStore: store)
        XCTAssertEqual(coordinator.series, series)
        XCTAssertEqual(coordinator.phase, .settled)
        XCTAssertEqual(coordinator.lastSettledAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testRefreshPersistsChartSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("coord-chart-persist-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UsageChartSnapshotStore(applicationSupportRoot: root)
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.chart-persist.sig"))
        let dayMs = UsageDayKey.utcDay(containing: Date()).utcMidnightMs
        let client = DashboardClient { request in
            let method = request.url?.lastPathComponent ?? ""
            if method == "GetDailySpendByCategory" {
                return try usageCoordOK(request, usageCoordDailyJSON(dayMs: dayMs, tokens: 21))
            }
            if method == "GetAggregatedUsageEvents" {
                return try usageCoordOK(request, usageCoordAggregateJSON(input: 21))
            }
            return try usageCoordOK(request, #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#)
        }
        let coordinator = UsageSeriesCoordinator(
            refresher: UsageSeriesRefresher(client: client),
            tokenSummaryRefresher: UsageTokenSummaryRefresher(client: client),
            insightsRefresher: UsageInsightsRefresher(client: client),
            chartSnapshotStore: store
        )
        coordinator.configure(
            loadCredentials: {
                [UsageSeriesRefresher.SeatCredential(seatID: .seat1, access: token)]
            },
            connectedScopes: { [(.allAccounts, "All Accounts")] },
            onChange: {}
        )
        coordinator.refresh()
        await usageCoordWait(coordinator) { $0.phase == .settled && $0.series != nil }
        let loaded = store.load()
        XCTAssertEqual(loaded?.series?.points.first(where: { $0.tokens == 21 })?.tokens, 21)
        XCTAssertNotNil(loaded?.settledAt)
    }
}

@MainActor
private func usageCoordMake(client: DashboardClient, timeZone: TimeZone = .current) -> UsageSeriesCoordinator {
    UsageSeriesCoordinator(
        refresher: UsageSeriesRefresher(client: client),
        tokenSummaryRefresher: UsageTokenSummaryRefresher(client: client),
        insightsRefresher: UsageInsightsRefresher(client: client),
        timeZone: timeZone
    )
}

@MainActor
private func usageCoordWait(
    _ coordinator: UsageSeriesCoordinator,
    timeoutMs: Int = 3000,
    predicate: (UsageSeriesCoordinator) -> Bool
) async {
    let steps = max(timeoutMs / 20, 1)
    for _ in 0..<steps {
        if predicate(coordinator) { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

private func usageCoordOK(_ request: URLRequest, _ json: String) throws -> (Data, URLResponse) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (Data(json.utf8), response)
}

private func usageCoordPeriodContains(_ request: URLRequest, day: UsageDayKey) -> Bool {
    usageCoordWindowContains(request, day: day)
}

private func usageCoordWindowContains(_ request: URLRequest, day: UsageDayKey) -> Bool {
    guard let body = request.httpBody,
          let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    else { return false }
    let start = (object["periodStartMs"] as? NSNumber)?.int64Value
        ?? (object["startDate"] as? NSNumber)?.int64Value
        ?? (object["periodStartMs"] as? Int64)
        ?? (object["startDate"] as? Int64)
    let end = (object["periodEndMs"] as? NSNumber)?.int64Value
        ?? (object["endDate"] as? NSNumber)?.int64Value
        ?? (object["periodEndMs"] as? Int64)
        ?? (object["endDate"] as? Int64)
    guard let start, let end else { return false }
    let ms = day.utcMidnightMs
    return ms >= start && ms < end
}

private func usageCoordDailyJSON(dayMs: Int64, tokens: Int64) -> String {
    #"{"dailySpend":[{"day":"\#(dayMs)","category":"default","totalTokens":"\#(tokens)"}]}"#
}

private func usageCoordAggregateJSON(input: Int64) -> String {
    #"{"totalInputTokens":"\#(input)","totalOutputTokens":0,"totalCacheWriteTokens":0,"totalCacheReadTokens":0,"aggregations":[{"modelIntent":"solo","inputTokens":"\#(input)","outputTokens":0,"cacheReadTokens":0}]}"#
}

private actor CoordinatorStallGate {
    private var holdFirst = false
    private var firstHeld = false
    private var release = false
    private var isFirst = true
    private var fastTokens: Int64 = 1

    func armFirstHold(hold: Bool = true) {
        holdFirst = hold
        firstHeld = false
        release = false
        isFirst = true
        fastTokens = 1
    }

    func waitIfFirst() async {
        guard holdFirst, isFirst else { return }
        isFirst = false
        firstHeld = true
        while !release {
            await Task.yield()
        }
    }

    func waitUntilFirstHeld() async {
        while !firstHeld {
            await Task.yield()
        }
    }

    func releaseFirst() {
        release = true
    }

    func setFastTokens(_ value: Int64) {
        fastTokens = value
    }

    func tokensForCurrentRequest() -> Int64 {
        fastTokens
    }
}

private actor AllTimeMonthStall {
    private var hold = true

    func wait() async {
        while hold {
            await Task.yield()
        }
    }

    func release() {
        hold = false
    }
}
