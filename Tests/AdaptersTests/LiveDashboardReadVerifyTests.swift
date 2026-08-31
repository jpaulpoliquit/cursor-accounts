import CursorBarAdapters
import CursorBarDomain
import XCTest

/// Opt-in live read-only probe. Skips unless LIVE_DASHBOARD_VERIFY=1 or flag file. Never mutates SetHardLimit.
final class LiveDashboardReadVerifyTests: XCTestCase {
    private static let flagName = "cursorbar-live-dashboard-verify"

    func testLiveReadOnlyDashboardRPCsForImportedSession() async throws {
        let enabledByEnv =
            ProcessInfo.processInfo.environment["LIVE_DASHBOARD_VERIFY"] == "1"
            || ProcessInfo.processInfo.environment["CURSORBAR_LIVE"] == "1"
        let tmpFlag = NSTemporaryDirectory() + Self.flagName
        let documentedFlag = "/tmp/" + Self.flagName
        let enabledByFlag =
            FileManager.default.fileExists(atPath: tmpFlag)
            || FileManager.default.fileExists(atPath: documentedFlag)
        guard enabledByEnv || enabledByFlag else {
            throw XCTSkip("Enable via LIVE_DASHBOARD_VERIFY=1 or /tmp/cursorbar-live-dashboard-verify")
        }

        let imported = try CursorDesktopSessionSource().load()
        guard let imported else {
            return XCTFail("No Cursor desktop session available")
        }
        XCTAssertFalse(imported.access.rawValue.hasPrefix("crsr_"))
        let access = try XCTUnwrap(ConnectReadyAccessToken(imported.access))

        let client = DashboardClient()
        let meProfile = try await client.getMeProfile(access: access)
        let me = meProfile.identity
        print("LIVE get_me_usable=\(me.isUsableForPresentation)")
        print("LIVE get_me_has_email=\(me.email != nil)")
        print("LIVE get_me_has_display_name=\(me.displayName != nil)")
        print("LIVE get_me_created_at_parseable=\(meProfile.createdAt != nil)")
        XCTAssertTrue(me.isUsableForPresentation, "GetMe must yield email or displayName for login hydration")

        let plan = try await client.getPlanInfo(access: access)
        let period = try await client.getCurrentPeriodUsage(access: access)
        let hardLimit = try await client.getHardLimit(access: access)
        let credits = try await client.getCreditGrantsBalance(access: access)
        let policy = try await client.getUsageLimitPolicyStatus(access: access)

        // Redacted evidence only. Never print tokens, emails, or Authorization material.
        print("LIVE plan_name=\(plan.name)")
        print("LIVE included_amount_cents=\(plan.includedAmountCents.map { String($0.cents) } ?? "nil")")
        print("LIVE price_present=\(plan.price != nil)")
        print("LIVE auto_percent=\(period.usage.autoPercentUsed.percent)")
        print("LIVE api_percent=\(period.usage.apiPercentUsed.percent)")
        print("LIVE total_percent=\(period.usage.totalPercentUsed.percent)")
        switch hardLimit {
        case .off:
            print("LIVE hard_limit_mode=off")
        case .fixed(let dollars):
            print("LIVE hard_limit_mode=fixed")
            print("LIVE hard_limit_dollars=\(dollars.amount)")
        case .unlimited:
            print("LIVE hard_limit_mode=unlimited")
        }
        if let used = period.spendLimitUsage?.individualUsed {
            print("LIVE individual_used_cents=\(used.cents)")
        } else {
            print("LIVE individual_used_cents=nil")
        }
        if let limit = period.spendLimitUsage?.individualLimit {
            print("LIVE individual_limit_cents=\(limit.cents)")
        }
        switch credits {
        case .absent:
            print("LIVE credits=absent")
        case .present(let balance, let total, let used):
            print("LIVE credits_balance_cents=\(balance.cents)")
            print("LIVE credits_total_cents=\(total.cents)")
            print("LIVE credits_used_cents=\(used.cents)")
        }
        print("LIVE policy_can_configure=\(policy.canConfigureSpendLimit.map(String.init(describing:)) ?? "nil")")
        print("LIVE policy_can_adjust=\(policy.canAdjustOnDemand.map(String.init(describing:)) ?? "nil")")

        let cycle = try await client.getMonthlyBillingCycle(access: access)
        print("LIVE cycle_start_ms=\(cycle.startMs)")
        print("LIVE cycle_end_ms=\(cycle.endMs)")
        XCTAssertGreaterThan(cycle.endMs, cycle.startMs)

        let tz = TimeZone.current
        let currentMonth = UsageRange.defaultMonth(timeZone: tz)
        let previousMonth = try XCTUnwrap(currentMonth.previous())
        let currentBounds = currentMonth.utcRequestIntervalMs(timeZone: tz)
        let previousBounds = previousMonth.utcRequestIntervalMs(timeZone: tz)
        let currentRows = try await client.getDailySpendByCategory(
            access: access,
            periodStartMs: currentBounds.startMs,
            periodEndMs: currentBounds.endExclusiveMs
        )
        let previousRows = try await client.getDailySpendByCategory(
            access: access,
            periodStartMs: previousBounds.startMs,
            periodEndMs: previousBounds.endExclusiveMs
        )
        print("LIVE month_current_row_count=\(currentRows.count)")
        print("LIVE month_previous_row_count=\(previousRows.count)")
        print("LIVE month_current_token_sum=\(currentRows.reduce(Int64(0)) { $0 + $1.totalTokens })")
        print("LIVE month_previous_token_sum=\(previousRows.reduce(Int64(0)) { $0 + $1.totalTokens })")
        XCTAssertGreaterThan(currentRows.count, 0)

        let today = UsageDayKey.utcDay(containing: Date())
        let range = currentMonth.chartUTCDays(timeZone: tz)
        let rows = currentRows
        let distinctDays = Set(rows.map(\.day))
        let tokenSum = rows.reduce(Int64(0)) { $0 + $1.totalTokens }
        let costAvailable = rows.contains(where: { $0.spendCents != nil })
        let seatSeries = UsageSeriesAggregator.seatSeries(
            seatID: .seat1,
            rows: rows,
            rangeStart: range.start,
            rangeEnd: range.end
        )
        let nonEmptyPoints = seatSeries.points.filter { $0.tokens > 0 || ($0.spendCents ?? 0) > 0 }.count
        print("LIVE graph_row_count=\(rows.count)")
        print("LIVE graph_distinct_days=\(distinctDays.count)")
        print("LIVE graph_token_sum=\(tokenSum)")
        print("LIVE graph_cost_available=\(costAvailable)")
        print("LIVE graph_non_empty_points=\(nonEmptyPoints)")

        XCTAssertFalse(plan.name.isEmpty)
        XCTAssertGreaterThanOrEqual(period.usage.totalPercentUsed.percent, 0)
        XCTAssertGreaterThan(rows.count, 0, "expected non-empty GetDailySpendByCategory rows")
        XCTAssertGreaterThan(distinctDays.count, 0)
        XCTAssertGreaterThan(tokenSum, 0)
        XCTAssertGreaterThan(nonEmptyPoints, 0)

        let aggregateBounds = currentMonth.utcRequestIntervalMs(timeZone: tz)
        let aggregate = try await client.getAggregatedUsageEvents(
            access: access,
            startDateMs: aggregateBounds.startMs,
            endDateMs: aggregateBounds.endExclusiveMs,
            seatID: .seat1
        )
        let sum4 = aggregate.totals.total
        print("LIVE aggregate_sum4_positive=\(sum4 > 0)")
        print("LIVE aggregate_cache_read_non_negative=\(aggregate.totals.cacheRead >= 0)")
        print("LIVE aggregate_model_count=\(aggregate.models.count)")
        print("LIVE aggregate_has_models=\(!aggregate.models.isEmpty)")
        XCTAssertGreaterThanOrEqual(aggregate.totals.input, 0)
        XCTAssertGreaterThanOrEqual(aggregate.totals.output, 0)
        XCTAssertGreaterThanOrEqual(aggregate.totals.cacheWrite, 0)
        XCTAssertGreaterThanOrEqual(aggregate.totals.cacheRead, 0)
        XCTAssertEqual(
            aggregate.totals.total,
            aggregate.totals.input
                + aggregate.totals.output
                + aggregate.totals.cacheWrite
                + aggregate.totals.cacheRead
        )
        if tokenSum > 0 {
            XCTAssertGreaterThan(sum4, 0)
            XCTAssertFalse(aggregate.models.isEmpty)
        }
    }
}
