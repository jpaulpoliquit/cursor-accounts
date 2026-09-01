@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class DashboardUsageEventsWireTests: XCTestCase {
    func testPersonalRequestOmitsTeamAndUserIds() async throws {
        nonisolated(unsafe) var seenBody: Data?
        let client = DashboardClient { request in
            seenBody = request.httpBody
            XCTAssertEqual(request.url?.lastPathComponent, "GetFilteredUsageEvents")
            return try Self.ok(
                request,
                #"""
                {
                  "totalUsageEventsCount": 1,
                  "usageEventsDisplay": [
                    {
                      "timestamp": "1786318505243",
                      "model": "cursor-grok-4.5-high-fast",
                      "kind": "USAGE_EVENT_KIND_INCLUDED_IN_ULTRA",
                      "isTokenBasedCall": true,
                      "isHeadless": false,
                      "chargedCents": 1.5,
                      "usageBasedCosts": "$0.12",
                      "conversationId": "conv-should-not-survive",
                      "userEmail": "secret@example.com",
                      "tokenUsage": {
                        "inputTokens": "10",
                        "outputTokens": 2,
                        "cacheReadTokens": "3",
                        "cacheWriteTokens": 4,
                        "totalCents": 9
                      }
                    }
                  ],
                  "usageEvents": []
                }
                """#
            )
        }
        let page = try await client.getFilteredUsageEventsPage(
            access: Self.jwt,
            startDateMs: 1,
            endDateMs: 2,
            page: 1
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(seenBody)) as? [String: Any])
        XCTAssertNil(object["teamId"])
        XCTAssertNil(object["userId"])
        XCTAssertEqual((object["page"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(
            (object["pageSize"] as? NSNumber)?.intValue,
            Int(DashboardClient.filteredUsageEventsPageSize)
        )
        XCTAssertEqual(page.totalCount, 1)
        XCTAssertEqual(page.requests.count, 1)
        XCTAssertEqual(page.requests[0].timestampMs, 1_786_318_505_243)
        XCTAssertEqual(page.requests[0].tokens?.total, 19)
        XCTAssertEqual(page.requests[0].kind, .includedInUltra)
        XCTAssertEqual(page.requests[0].usageValueCents, 2)
        XCTAssertEqual(page.requests[0].onDemandChargedCents, 12)
        // Privacy: domain request has no conversation/email fields to leak.
        let mirror = Mirror(reflecting: page.requests[0])
        let labels = Set(mirror.children.compactMap(\.label))
        XCTAssertFalse(labels.contains("conversationId"))
        XCTAssertFalse(labels.contains("userEmail"))
    }

    func testNumericTimestampAndOmittedTokenUsage() throws {
        let json = #"""
        {
          "totalUsageEventsCount": 2,
          "usageEventsDisplay": [
            {"timestamp": 100, "model": "a", "kind": "USAGE_EVENT_KIND_USAGE_BASED"},
            {"timestamp": "200", "model": "b", "kind": "USAGE_EVENT_KIND_USAGE_BASED",
             "tokenUsage": {"inputTokens": 1, "outputTokens": 1, "cacheReadTokens": 0, "cacheWriteTokens": 0}}
          ],
          "usageEvents": []
        }
        """#
        let dto = try JSONDecoder().decode(GetFilteredUsageEventsWireDTO.self, from: Data(json.utf8))
        let parsed = try DashboardUsageEventsWire.requests(from: dto)
        XCTAssertEqual(parsed.totalCount, 2)
        XCTAssertNil(parsed.requests[0].tokens)
        XCTAssertEqual(parsed.requests[1].tokens?.total, 2)
    }

    func testPagerStopsOnShortPageAndSortsAscending() async throws {
        let pager = UsageEventsPager(policy: .init(pageSize: 2, maxEvents: 10_000))
        nonisolated(unsafe) var pages: [Int32] = []
        let result = try await pager.fetchAll { page, pageSize in
            pages.append(page)
            XCTAssertEqual(pageSize, 2)
            if page == 1 {
                return (
                    [
                        ActivityRequest(
                            timestampMs: 300,
                            model: "m",
                            kind: .usageBased,
                            tokens: nil,
                            usageValueCents: nil,
                            onDemandChargedCents: nil,
                            isHeadless: false,
                            isTokenBasedCall: true
                        ),
                        ActivityRequest(
                            timestampMs: 200,
                            model: "m",
                            kind: .usageBased,
                            tokens: nil,
                            usageValueCents: nil,
                            onDemandChargedCents: nil,
                            isHeadless: false,
                            isTokenBasedCall: true
                        ),
                    ],
                    3
                )
            }
            return (
                [
                    ActivityRequest(
                        timestampMs: 100,
                        model: "m",
                        kind: .usageBased,
                        tokens: nil,
                        usageValueCents: nil,
                        onDemandChargedCents: nil,
                        isHeadless: false,
                        isTokenBasedCall: true
                    ),
                ],
                3
            )
        }
        XCTAssertEqual(pages, [1, 2])
        XCTAssertEqual(result.requests.map(\.timestampMs), [100, 200, 300])
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.reportedTotal, 3)
    }

    func testPagerRespectsMaxEventsCap() async throws {
        let pager = UsageEventsPager(policy: .init(pageSize: 2, maxEvents: 3))
        let result = try await pager.fetchAll { page, _ in
            (
                [
                    ActivityRequest(
                        timestampMs: Int64(1000 - page * 10),
                        model: "m",
                        kind: .usageBased,
                        tokens: nil,
                        usageValueCents: nil,
                        onDemandChargedCents: nil,
                        isHeadless: false,
                        isTokenBasedCall: true
                    ),
                    ActivityRequest(
                        timestampMs: Int64(999 - page * 10),
                        model: "m",
                        kind: .usageBased,
                        tokens: nil,
                        usageValueCents: nil,
                        onDemandChargedCents: nil,
                        isHeadless: false,
                        isTokenBasedCall: true
                    ),
                ],
                100
            )
        }
        XCTAssertEqual(result.requests.count, 3)
        XCTAssertTrue(result.truncated)
    }

    func testDedupeSameSubjectKeepsFirstSeatOnly() {
        // Two JWTs with identical sub claim payload (signature not verified locally).
        let jwtA = Self.jwtWithSubject("user-1")
        let jwtB = Self.jwtWithSubject("user-1")
        let jwtC = Self.jwtWithSubject("user-2")
        let creds = [
            SeatUsageRefresher.SeatCredential(seatID: .seat1, access: jwtA),
            SeatUsageRefresher.SeatCredential(seatID: .seat2, access: jwtB),
            SeatUsageRefresher.SeatCredential(seatID: .seat3, access: jwtC),
        ]
        let deduped = UsageInsightsRefresher.dedupeSameSubject(creds)
        XCTAssertEqual(deduped.map(\.seatID), [.seat1, .seat3])
    }

    func testHistoryWarmDropsOnSignOutCancel() async throws {
        nonisolated(unsafe) var hits = 0
        let client = DashboardClient { request in
            hits += 1
            try await Task.sleep(nanoseconds: 30_000_000)
            return try Self.ok(
                request,
                #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
            )
        }
        let refresher = UsageInsightsRefresher(client: client)
        let cred = SeatUsageRefresher.SeatCredential(seatID: .seat1, access: Self.jwt)
        async let warm = refresher.warmSeatHistory(
            credential: cred,
            timeZone: TimeZone(identifier: "Asia/Taipei")!,
            budget: HistoryWarmBudget(maxMonths: 3, maxEvents: 10_000)
        )
        try await Task.sleep(nanoseconds: 5_000_000)
        await refresher.dropSeatCaches(seatID: .seat1)
        let phase = await warm
        XCTAssertEqual(phase, .cancelled)
        XCTAssertGreaterThanOrEqual(hits, 1)
    }

    func testCancelWarmForOneSeatDoesNotAbortAnotherSeatWarm() async throws {
        let gate = WarmIsolationGate()
        let tokenA = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.warm-seatA.sig"))
        let tokenB = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.warm-seatB.sig"))
        let client = DashboardClient { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if auth.contains("warm-seatA") {
                await gate.markAStarted()
                await gate.waitUntilReleaseA()
            }
            return try Self.ok(
                request,
                #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
            )
        }
        let refresher = UsageInsightsRefresher(client: client)
        let credA = SeatUsageRefresher.SeatCredential(seatID: .seat1, access: tokenA)
        let credB = SeatUsageRefresher.SeatCredential(seatID: .seat2, access: tokenB)
        let tz = TimeZone(identifier: "Asia/Taipei")!
        async let warmA = refresher.warmSeatHistory(
            credential: credA,
            timeZone: tz,
            budget: HistoryWarmBudget(maxMonths: 2, maxEvents: 10_000)
        )
        async let warmB = refresher.warmSeatHistory(
            credential: credB,
            timeZone: tz,
            budget: HistoryWarmBudget(maxMonths: 2, maxEvents: 10_000)
        )
        await gate.waitUntilAStarted()
        await refresher.dropSeatCaches(seatID: .seat1)
        await gate.releaseA()
        let phaseA = await warmA
        let phaseB = await warmB
        XCTAssertEqual(phaseA, .cancelled)
        guard case .settled = phaseB else {
            return XCTFail("seat2 warm must complete independently, got \(phaseB)")
        }
    }

    func testStaleWarmCompletionCannotApplyAfterSeatReconnectGenerationBump() async throws {
        let gate = WarmIsolationGate()
        let client = DashboardClient { request in
            await gate.markAStarted()
            await gate.waitUntilReleaseA()
            return try Self.ok(
                request,
                #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
            )
        }
        let refresher = UsageInsightsRefresher(client: client)
        let cred = SeatUsageRefresher.SeatCredential(seatID: .seat1, access: Self.jwt)
        let tz = TimeZone(identifier: "Asia/Taipei")!
        async let first = refresher.warmSeatHistory(
            credential: cred,
            timeZone: tz,
            budget: HistoryWarmBudget(maxMonths: 1, maxEvents: 10_000)
        )
        await gate.waitUntilAStarted()
        // Reconnect / restart warm for same seat advances generation.
        async let second = refresher.warmSeatHistory(
            credential: cred,
            timeZone: tz,
            budget: HistoryWarmBudget(maxMonths: 1, maxEvents: 10_000)
        )
        await gate.releaseA()
        let firstPhase = await first
        let secondPhase = await second
        XCTAssertEqual(firstPhase, .cancelled)
        guard case .settled = secondPhase else {
            return XCTFail("replacement warm must settle, got \(secondPhase)")
        }
    }

    func testInsightsRefresherGenerationCancelDiscards() async throws {
        let client = DashboardClient { request in
            try await Task.sleep(nanoseconds: 50_000_000)
            return try Self.ok(
                request,
                #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
            )
        }
        let refresher = UsageInsightsRefresher(client: client)
        async let first = refresher.refresh(
            credentials: [SeatUsageRefresher.SeatCredential(seatID: .seat1, access: Self.jwt)],
            scope: .account(.seat1),
            range: .month(YearMonth(year: 2026, month: 8)),
            timeZone: TimeZone(identifier: "Asia/Taipei")!
        )
        try await Task.sleep(nanoseconds: 5_000_000)
        await refresher.bumpGenerationForTests()
        let commit = await first
        XCTAssertEqual(commit, .discarded)
    }

    func testAllFailRefreshKeepsLastKnownInsights() async throws {
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.payload.signature"))
        let cred = SeatUsageRefresher.SeatCredential(seatID: .seat1, access: token)
        let range = UsageRange.month(YearMonth.current())
        let tz = TimeZone(identifier: "Asia/Taipei")!
        let okJSON = #"""
        {"totalUsageEventsCount":2,"usageEventsDisplay":[
          {"timestamp":"1722470400000","model":"m","kind":"USAGE_EVENT_KIND_USAGE_BASED",
           "tokenUsage":{"inputTokens":1,"outputTokens":1,"cacheReadTokens":0,"cacheWriteTokens":0}},
          {"timestamp":"1722474000000","model":"m","kind":"USAGE_EVENT_KIND_USAGE_BASED",
           "tokenUsage":{"inputTokens":1,"outputTokens":1,"cacheReadTokens":0,"cacheWriteTokens":0}}
        ],"usageEvents":[]}
        """#
        nonisolated(unsafe) var calls = 0
        let client = DashboardClient { request in
            calls += 1
            if calls == 1 {
                return try Self.ok(request, okJSON)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        let refresher = UsageInsightsRefresher(client: client)
        let seed = await refresher.refresh(credentials: [cred], scope: .account(.seat1), range: range, timeZone: tz)
        guard case .applied(let seeded) = seed else { return XCTFail("seed apply") }
        XCTAssertEqual(seeded.insights.totalRequests, 2)

        let afterFail = await refresher.refresh(credentials: [cred], scope: .account(.seat1), range: range, timeZone: tz)
        guard case .applied(let kept) = afterFail else { return XCTFail("expected applied keep") }
        XCTAssertEqual(kept.insights.totalRequests, 2)
        let lastKnown = await refresher.lastKnownInsights()
        XCTAssertEqual(lastKnown?.totalRequests, 2)
        guard case .failed? = kept.outcomes[.seat1] else {
            return XCTFail("seat should be failed")
        }
    }

    func testStaleFetchCannotCommitCacheAfterGenerationBump() async throws {
        let gate = WarmIsolationGate()
        let token = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.stale-cache.sig"))
        let month = YearMonth.current().previous
        let range = UsageRange.month(month)
        nonisolated(unsafe) var calls = 0
        let client = DashboardClient { request in
            calls += 1
            if calls == 1 {
                await gate.markAStarted()
                await gate.waitUntilReleaseA()
                return try Self.ok(
                    request,
                    #"{"totalUsageEventsCount":1,"usageEventsDisplay":[{"timestamp":"1722470400000","model":"m","kind":"USAGE_EVENT_KIND_USAGE_BASED","tokenUsage":{"inputTokens":111,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0}}],"usageEvents":[]}"#
                )
            }
            return try Self.ok(
                request,
                #"{"totalUsageEventsCount":1,"usageEventsDisplay":[{"timestamp":"1722470400000","model":"m","kind":"USAGE_EVENT_KIND_USAGE_BASED","tokenUsage":{"inputTokens":222,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0}}],"usageEvents":[]}"#
            )
        }
        let refresher = UsageInsightsRefresher(client: client)
        let cred = SeatUsageRefresher.SeatCredential(seatID: .seat1, access: token)
        let tz = TimeZone(identifier: "Asia/Taipei")!
        async let slow = refresher.refresh(
            credentials: [cred],
            scope: .account(.seat1),
            range: range,
            timeZone: tz,
            includeMonthOverMonth: false
        )
        await gate.waitUntilAStarted()
        await refresher.bumpGenerationForTests()
        await gate.releaseA()
        let slowCommit = await slow
        XCTAssertEqual(slowCommit, .discarded)
        let fast = await refresher.refresh(
            credentials: [cred],
            scope: .account(.seat1),
            range: range,
            timeZone: tz,
            includeMonthOverMonth: false
        )
        guard case .applied(let report) = fast else { return XCTFail("fast apply") }
        XCTAssertEqual(report.insights.totalRequests, 1)
        XCTAssertEqual(calls, 2, "stale slow completion must not satisfy historical cache")
        let lastKnown = await refresher.lastKnownInsights()
        XCTAssertEqual(lastKnown?.totalRequests, 1)
    }

    func testDropSeatCachesPreventsSameSeatIDResurrection() async throws {
        let tokenA = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.insightsA.sig"))
        let tokenB = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.insightsB.sig"))
        let month = YearMonth.current().previous
        let range = UsageRange.month(month)
        nonisolated(unsafe) var calls = 0
        let client = DashboardClient { request in
            calls += 1
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            let input = auth.contains("insightsA") ? 111 : 222
            return try Self.ok(
                request,
                #"{"totalUsageEventsCount":1,"usageEventsDisplay":[{"timestamp":"1722470400000","model":"m","kind":"USAGE_EVENT_KIND_USAGE_BASED","tokenUsage":{"inputTokens":\#(input),"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0}}],"usageEvents":[]}"#
            )
        }
        let refresher = UsageInsightsRefresher(client: client)
        let credA = SeatUsageRefresher.SeatCredential(seatID: .seat1, access: tokenA)
        let credB = SeatUsageRefresher.SeatCredential(seatID: .seat1, access: tokenB)
        let tz = TimeZone(identifier: "Asia/Taipei")!
        let appliedA = await refresher.refresh(
            credentials: [credA],
            scope: .account(.seat1),
            range: range,
            timeZone: tz,
            includeMonthOverMonth: false
        )
        guard case .applied(let reportA) = appliedA else { return XCTFail("seed A") }
        XCTAssertEqual(reportA.insights.totalRequests, 1)
        XCTAssertEqual(calls, 1)
        await refresher.dropSeatCaches(seatID: .seat1)
        calls = 0
        let appliedB = await refresher.refresh(
            credentials: [credB],
            scope: .account(.seat1),
            range: range,
            timeZone: tz,
            includeMonthOverMonth: false
        )
        guard case .applied(let reportB) = appliedB else { return XCTFail("apply B") }
        XCTAssertEqual(calls, 1, "B must not hit A's immutable month cache")
        XCTAssertEqual(reportB.insights.totalRequests, 1)
    }

    func testAllTimeKeepsBothSeatsWhenOneMonthFails() async throws {
        let tokenA = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.keepA.sig"))
        let tokenB = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "header.keepB.sig"))
        let tz = TimeZone(secondsFromGMT: 0)!
        let july = UsageDayKey(year: 2026, month: 7, day: 1)
        let august = UsageDayKey(year: 2026, month: 8, day: 1)
        let client = DashboardClient { request in
            let path = request.url?.lastPathComponent ?? ""
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if path == "GetFilteredUsageEvents" {
                let body = request.httpBody ?? Data()
                let object = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
                let start = (object["startDate"] as? NSNumber)?.int64Value ?? 0
                let end = (object["endDate"] as? NSNumber)?.int64Value ?? 0
                if auth.contains("keepA"), start < august.utcMidnightMs {
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 500,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return (Data(), response)
                }
                let stamp = auth.contains("keepA")
                    ? august.utcMidnightMs + 12 * 3_600_000
                    : july.utcMidnightMs + 12 * 3_600_000
                if stamp < start || stamp >= end {
                    return try Self.ok(
                        request,
                        #"{"totalUsageEventsCount":0,"usageEventsDisplay":[],"usageEvents":[]}"#
                    )
                }
                return try Self.ok(
                    request,
                    """
                    {
                      "totalUsageEventsCount": 1,
                      "usageEventsDisplay": [
                        {"timestamp":"\(stamp)","model":"m","kind":"USAGE_EVENT_KIND_USAGE_BASED",
                         "tokenUsage":{"inputTokens":1,"outputTokens":1,"cacheReadTokens":0,"cacheWriteTokens":0}}
                      ],
                      "usageEvents": []
                    }
                    """
                )
            }
            return try Self.ok(request, "{}")
        }
        let refresher = UsageInsightsRefresher(client: client)
        let commit = await refresher.refresh(
            credentials: [
                .init(seatID: .seat1, access: tokenA),
                .init(seatID: .seat2, access: tokenB),
            ],
            scope: .allAccounts,
            range: .allTime(start: july, end: UsageDayKey(year: 2026, month: 8, day: 14)),
            timeZone: tz,
            includeMonthOverMonth: false,
            seatStarts: [
                .seat1: july,
                .seat2: july,
            ]
        )
        guard case .applied(let report) = commit else {
            return XCTFail("expected applied insights")
        }
        XCTAssertEqual(report.insights.coverage.successfulSeatCount, 2)
        XCTAssertEqual(report.insights.totalRequests, 2)
        XCTAssertTrue(report.insights.coverage.truncated)
        let seats = Set(report.insights.days.flatMap(\.contributions).map(\.seatID))
        XCTAssertEqual(seats, [.seat1, .seat2])
        XCTAssertEqual(report.insights.days.first?.day.month, 7)
    }

    private static var jwt: ConnectReadyAccessToken {
        ConnectReadyAccessToken(validatedJWT: "header.payload.signature")!
    }

    private static func jwtWithSubject(_ subject: String) -> ConnectReadyAccessToken {
        let payload = try! JSONSerialization.data(withJSONObject: ["sub": subject])
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return ConnectReadyAccessToken(validatedJWT: "hdr.\(encoded).sig")!
    }

    private static func ok(_ request: URLRequest, _ json: String) throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(json.utf8), response)
    }
}

private actor WarmIsolationGate {
    private var aStarted = false
    private var aReleased = false

    func markAStarted() {
        aStarted = true
    }

    func waitUntilAStarted() async {
        while !aStarted {
            await Task.yield()
        }
    }

    func waitUntilReleaseA() async {
        while !aReleased {
            await Task.yield()
        }
    }

    func releaseA() {
        aReleased = true
    }
}
