@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class AuthEngineTests: XCTestCase {
    func testResolvedEmptySeatSkipsOccupiedPreferred() async throws {
        let ghost = try Self.record(seat: .seat1, sub: "ghost", access: "a.b.c", refresh: "r")
        let store = UncheckedMemorySeatStore(records: [ghost])
        let engine = AuthEngine(
            store: store,
            browser: NullBrowserPresenter()
        )
        let resolved = await engine.resolvedEmptySeat(preferred: .seat1)
        XCTAssertEqual(resolved, .seat2)
    }

    func testBeginEmptySeatLoginOnUnreadableSeatIsSeatNotEmpty() async {
        let store = ThrowingSeatStore(unreadable: [.seat1])
        let engine = AuthEngine(
            store: store,
            browser: NullBrowserPresenter()
        )
        let (presentation, task) = await engine.beginEmptySeatLogin(seatID: .seat1)
        XCTAssertNil(presentation)
        let outcome = await task.value
        XCTAssertEqual(outcome, .seatNotEmpty)
        let resolved = await engine.resolvedEmptySeat(preferred: .seat1)
        XCTAssertEqual(resolved, .seat2)
    }

    func testBeginEmptySeatLoginOnOccupiedPreferredIsSeatNotEmpty() async throws {
        let ghost = try Self.record(seat: .seat1, sub: "ghost", access: "a.b.c", refresh: "r")
        let store = UncheckedMemorySeatStore(records: [ghost])
        let engine = AuthEngine(
            store: store,
            browser: NullBrowserPresenter()
        )
        let (presentation, task) = await engine.beginEmptySeatLogin(seatID: .seat1)
        XCTAssertNil(presentation)
        let outcome = await task.value
        XCTAssertEqual(outcome, .seatNotEmpty)
    }

    func testPollSubjectOnlyJWTThenGetMeConnectsWithIdentity() async throws {
        nonisolated(unsafe) var pollCount = 0
        nonisolated(unsafe) var sleepMs: [Int] = []
        nonisolated(unsafe) var progressEvents: [DeviceLoginProgress] = []
        let jwt = Self.unsignedJWT(sub: "login-user", exp: 2_000_000_000)
        let http = AuthHTTPClient { request in
            XCTAssertTrue(request.url?.path.hasSuffix("/auth/poll") == true)
            pollCount += 1
            let status = pollCount < 3 ? 404 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            if status == 200 {
                let body = #"{"accessToken":"\#(jwt)","refreshToken":"refresh.login.jwt"}"#
                return (Data(body.utf8), response)
            }
            return (Data(), response)
        }
        let store = UncheckedMemorySeatStore()
        let sleeper = RecordingSleeper { sleepMs.append($0) }
        let entropy = FixedEntropy(
            bytes: Data(0..<32),
            uuid: UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!
        )
        let email = try XCTUnwrap(Email("user@example.com"))
        let displayName = try XCTUnwrap(DisplayName("john 5"))
        let hydrator = FixedIdentityHydrator(result: .success(
            try XCTUnwrap(HydratedAccountIdentity(email: email, displayName: displayName))
        ))
        let engine = AuthEngine(
            http: http,
            store: store,
            sleeper: sleeper,
            entropy: entropy,
            browser: NullBrowserPresenter(),
            identityHydrator: hydrator
        )
        let (presentation, task) = await engine.beginEmptySeatLogin(seatID: .seat2) { progress in
            progressEvents.append(progress)
        }
        let url = try XCTUnwrap(presentation?.loginURL)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value!) })
        XCTAssertEqual(items["uuid"], "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(items["challenge"], PKCE.challenge(forVerifier: PKCE.base64URLEncode(Data(0..<32))))
        XCTAssertEqual(items["mode"], "login")
        XCTAssertEqual(items["redirectTarget"], "cli")

        let outcome = await task.value
        XCTAssertEqual(outcome, .signedIn(placedOn: .seat2))
        XCTAssertEqual(pollCount, 3)
        XCTAssertEqual(hydrator.fetchCount, 1)
        XCTAssertTrue(progressEvents.contains(.finishingSignIn))
        XCTAssertEqual(sleepMs, [
            AuthClientConstants.pollDelayMs(attemptIndex: 0),
            AuthClientConstants.pollDelayMs(attemptIndex: 1),
        ])
        let saved = try XCTUnwrap(store.load(seatID: .seat2))
        XCTAssertEqual(saved.identity, .subject("login-user"))
        XCTAssertEqual(saved.email, email)
        XCTAssertEqual(saved.displayName, displayName)
        XCTAssertTrue(saved.hasUsablePresentationIdentity)
        XCTAssertEqual(try store.loadAll().count, 1)
        let plan = SeatRosterReconciler.plan(roster: try store.loadAll())
        XCTAssertEqual(plan.keep.map(\.seatID), [.seat2])
        XCTAssertTrue(plan.quarantineSeatIDs.isEmpty)
    }

    func testIdentityHydrationRetryKeepsFinishingWithoutPersisting() async throws {
        let jwt = Self.unsignedJWT(sub: "retry-user", exp: 2_000_000_000)
        let http = AuthHTTPClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"accessToken":"\#(jwt)","refreshToken":"refresh.retry"}"#
            return (Data(body.utf8), response)
        }
        let store = UncheckedMemorySeatStore()
        nonisolated(unsafe) var progressEvents: [DeviceLoginProgress] = []
        let email = try XCTUnwrap(Email("retry@example.com"))
        let hydrator = SequencingIdentityHydrator(results: [
            .failure(.transport(.httpStatus(503))),
            .failure(.transport(.transport)),
            .success(try XCTUnwrap(HydratedAccountIdentity(email: email, displayName: nil))),
        ])
        let engine = AuthEngine(
            http: http,
            store: store,
            sleeper: NoopSleeper(),
            browser: NullBrowserPresenter(),
            identityHydrator: hydrator
        )
        let (_, task) = await engine.beginEmptySeatLogin(seatID: .seat1) { progress in
            progressEvents.append(progress)
            if progress == .finishingSignIn {
                XCTAssertEqual(try? store.loadAll().count, 0)
            }
        }
        let outcome = await task.value
        XCTAssertEqual(outcome, .signedIn(placedOn: .seat1))
        XCTAssertEqual(hydrator.fetchCount, 3)
        XCTAssertTrue(progressEvents.contains(.finishingSignIn))
        XCTAssertEqual(try store.load(seatID: .seat1)?.email, email)
    }

    func testIdentityHydrationPermanentFailureLeavesNoPhantom() async throws {
        let jwt = Self.unsignedJWT(sub: "fail-user", exp: 2_000_000_000)
        let http = AuthHTTPClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"accessToken":"\#(jwt)","refreshToken":"refresh.fail"}"#
            return (Data(body.utf8), response)
        }
        let store = UncheckedMemorySeatStore()
        let hydrator = FixedIdentityHydrator(result: .failure(.transport(.httpStatus(401))))
        let engine = AuthEngine(
            http: http,
            store: store,
            sleeper: NoopSleeper(),
            browser: NullBrowserPresenter(),
            identityHydrator: hydrator
        )
        let (_, task) = await engine.beginEmptySeatLogin(seatID: .seat3)
        let outcome = await task.value
        XCTAssertEqual(outcome, .identityUnavailable)
        XCTAssertEqual(try store.loadAll().count, 0)
        XCTAssertEqual(hydrator.fetchCount, 1)
    }

    func testStaleSubjectOnlyRowStillQuarantinedAfterSuccessfulLoginPath() throws {
        let ghost = try Self.record(seat: .seat2, sub: "ghost", access: "a.b.c", refresh: "r")
        XCTAssertFalse(ghost.hasUsablePresentationIdentity)
        let plan = SeatRosterReconciler.plan(roster: [ghost])
        XCTAssertEqual(plan.quarantineSeatIDs, [.seat2])
        XCTAssertTrue(plan.keep.isEmpty)
    }

    func testNoPersistenceOn403CancelAndTimeout() async throws {
        let store = UncheckedMemorySeatStore()
        let deniedHTTP = AuthHTTPClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        let deniedEngine = AuthEngine(
            http: deniedHTTP,
            store: store,
            browser: NullBrowserPresenter(),
            identityHydrator: FixedIdentityHydrator(result: .failure(.decode))
        )
        let (_, deniedTask) = await deniedEngine.beginEmptySeatLogin(seatID: .seat1)
        let deniedOutcome = await deniedTask.value
        XCTAssertEqual(deniedOutcome, .denied)
        XCTAssertEqual(try store.loadAll().count, 0)

        let cancelHTTP = AuthHTTPClient { _ in
            throw CancellationError()
        }
        let cancelEngine = AuthEngine(
            http: cancelHTTP,
            store: store,
            browser: NullBrowserPresenter(),
            identityHydrator: FixedIdentityHydrator(result: .failure(.decode))
        )
        let (_, cancelTask) = await cancelEngine.beginEmptySeatLogin(seatID: .seat1)
        cancelTask.cancel()
        let cancelOutcome = await cancelTask.value
        XCTAssertTrue(cancelOutcome == .cancelled || cancelOutcome == .timedOut)
        XCTAssertEqual(try store.loadAll().count, 0)

        nonisolated(unsafe) var attempts = 0
        let timeoutHTTP = AuthHTTPClient { request in
            attempts += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        let timeoutEngine = AuthEngine(
            http: timeoutHTTP,
            store: store,
            sleeper: NoopSleeper(),
            browser: NullBrowserPresenter(),
            identityHydrator: FixedIdentityHydrator(result: .failure(.decode))
        )
        let (_, timeoutTask) = await timeoutEngine.beginEmptySeatLogin(seatID: .seat1)
        let timeoutOutcome = await timeoutTask.value
        XCTAssertEqual(timeoutOutcome, .timedOut)
        XCTAssertEqual(try store.loadAll().count, 0)
        XCTAssertEqual(attempts, AuthClientConstants.pollTransientFailureLimit)
    }

    func testRefreshSingleFlight() async throws {
        nonisolated(unsafe) var refreshCalls = 0
        let jwt = Self.unsignedJWT(sub: "s", exp: 1_800_000_000)
        let http = AuthHTTPClient { request in
            if request.url?.path.hasSuffix("/oauth/token") == true {
                refreshCalls += 1
                try await Task.sleep(nanoseconds: 50_000_000)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = #"{"access_token":"\#(jwt)","refresh_token":"rotated.refresh"}"#
                return (Data(body.utf8), response)
            }
            throw URLError(.badURL)
        }
        let record = try Self.record(
            seat: .seat1,
            sub: "s",
            access: Self.unsignedJWT(sub: "s", exp: 1),
            refresh: "old.refresh",
            expiresAt: Date(timeIntervalSince1970: 1),
            email: Email("s@example.com")
        )
        let store = UncheckedMemorySeatStore(records: [record])
        let clock = FixedClock(Date(timeIntervalSince1970: 100))
        let engine = AuthEngine(http: http, store: store, clock: clock)
        async let a = engine.connectAccess(for: .seat1)
        async let b = engine.connectAccess(for: .seat1)
        let left = try await a
        let right = try await b
        XCTAssertEqual(left.rawValue, jwt)
        XCTAssertEqual(right.rawValue, jwt)
        XCTAssertEqual(refreshCalls, 1)
        XCTAssertEqual(try store.load(seatID: .seat1)?.refresh.rawValue, "rotated.refresh")
    }

    func testAPIKeyCacheAndReexchangeAroundExp() async throws {
        nonisolated(unsafe) var exchangeCalls = 0
        let nearExp = Self.unsignedJWT(sub: "api-user", exp: 1_000_060)
        let later = Self.unsignedJWT(sub: "api-user", exp: 2_000_000_000)
        let http = AuthHTTPClient { request in
            XCTAssertEqual(request.url?.path, "/auth/exchange_user_api_key")
            exchangeCalls += 1
            let token = exchangeCalls == 1 ? nearExp : later
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"accessToken":"\#(token)","refreshToken":"api.refresh"}"#
            return (Data(body.utf8), response)
        }
        let store = UncheckedMemorySeatStore()
        let clock = FixedClock(Date(timeIntervalSince1970: 1_000_000))
        let email = try XCTUnwrap(Email("api@example.com"))
        let hydrator = FixedIdentityHydrator(result: .success(
            try XCTUnwrap(HydratedAccountIdentity(email: email, displayName: DisplayName("api user")))
        ))
        let engine = AuthEngine(http: http, store: store, clock: clock, identityHydrator: hydrator)
        let placed = try await engine.bindAPIKey(seatID: .seat3, rawKey: "crsr_unit_test_key")
        XCTAssertEqual(placed, .seat3)
        XCTAssertEqual(exchangeCalls, 1)
        XCTAssertEqual(try store.load(seatID: .seat3)?.access.rawValue, nearExp)
        XCTAssertEqual(try store.load(seatID: .seat3)?.email, email)
        // now == exp - skew, so connectAccess must re-exchange before returning.
        let first = try await engine.connectAccess(for: .seat3)
        XCTAssertEqual(first.rawValue, later)
        XCTAssertEqual(exchangeCalls, 2)
        let second = try await engine.connectAccess(for: .seat3)
        XCTAssertEqual(second.rawValue, later)
        XCTAssertEqual(exchangeCalls, 2)
        XCTAssertEqual(try store.load(seatID: .seat3)?.apiKey?.rawValue, "crsr_unit_test_key")
        XCTAssertNil(ConnectReadyAccessToken(try XCTUnwrap(AccessToken("crsr_unit_test_key"))))
    }

    func testLocalSignOutDeletesOnlyOwnedSeat() async throws {
        let store = UncheckedMemorySeatStore(records: [
            try Self.record(
                seat: .seat1,
                sub: "a",
                access: "a.access",
                refresh: "a.refresh",
                email: Email("a@example.com")
            ),
            try Self.record(
                seat: .seat2,
                sub: "b",
                access: "b.access",
                refresh: "b.refresh",
                email: Email("b@example.com")
            ),
        ])
        let engine = AuthEngine(store: store)
        try await engine.signOutLocally(seatID: .seat1)
        XCTAssertNil(try store.load(seatID: .seat1))
        XCTAssertNotNil(try store.load(seatID: .seat2))
    }

    func testDuplicateIdentityAfterLoginMapsExistingAccount() async throws {
        let jwt = Self.unsignedJWT(sub: "same-user", exp: 2_000_000_000)
        let email = try XCTUnwrap(Email("same@example.com"))
        let existing = try Self.record(
            seat: .seat1,
            sub: "same-user",
            access: jwt,
            refresh: "existing.refresh",
            email: email,
            displayName: DisplayName("kept")
        )
        let store = UncheckedMemorySeatStore(records: [existing])
        let http = AuthHTTPClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"accessToken":"\#(jwt)","refreshToken":"login.refresh"}"#
            return (Data(body.utf8), response)
        }
        let hydrator = FixedIdentityHydrator(result: .success(
            try XCTUnwrap(HydratedAccountIdentity(email: email, displayName: DisplayName("kept")))
        ))
        let engine = AuthEngine(
            http: http,
            store: store,
            sleeper: NoopSleeper(),
            browser: NullBrowserPresenter(),
            identityHydrator: hydrator
        )
        let (_, task) = await engine.beginEmptySeatLogin(seatID: .seat2)
        let duplicateOutcome = await task.value
        XCTAssertEqual(duplicateOutcome, .signedIn(placedOn: .seat1))
        XCTAssertNil(try store.load(seatID: .seat2))
        XCTAssertEqual(try store.load(seatID: .seat1)?.refresh.rawValue, "login.refresh")
        XCTAssertEqual(try store.loadAll().count, 1)
    }

    func testSecretTypesRedact() throws {
        let access = try XCTUnwrap(AccessToken("super-secret"))
        let refresh = try XCTUnwrap(RefreshToken("super-secret"))
        let key = try XCTUnwrap(APIKey("crsr_super_secret"))
        let ready = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: "jwt.secret.value"))
        XCTAssertEqual(String(describing: access), "<AccessToken>")
        XCTAssertEqual(String(describing: refresh), "<RefreshToken>")
        XCTAssertEqual(String(describing: key), "<APIKey>")
        XCTAssertEqual(String(describing: ready), "<ConnectReadyAccessToken>")
        XCTAssertFalse(String(reflecting: ready).contains("jwt.secret"))
    }

    private static func record(
        seat: SeatID,
        sub: String,
        access: String,
        refresh: String,
        expiresAt: Date? = Date(timeIntervalSince1970: 2_000_000_000),
        email: Email? = nil,
        displayName: DisplayName? = nil
    ) throws -> StoredSeatRecord {
        StoredSeatRecord(
            seatID: seat,
            identity: .subject(sub),
            access: try XCTUnwrap(AccessToken(access)),
            refresh: try XCTUnwrap(RefreshToken(refresh)),
            email: email,
            displayName: displayName,
            expiresAt: expiresAt,
            membershipType: nil,
            subscriptionStatus: nil
        )
    }

    private static func unsignedJWT(sub: String, exp: Int) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let payloadJSON = #"{"sub":"\#(sub)","exp":\#(exp)}"#
        let payload = Data(payloadJSON.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(payload).sig"
    }
}

private final class FixedIdentityHydrator: AccountIdentityHydrating, @unchecked Sendable {
    private let result: Result<HydratedAccountIdentity, DashboardClient.ClientError>
    private(set) var fetchCount = 0

    init(result: Result<HydratedAccountIdentity, DashboardClient.ClientError>) {
        self.result = result
    }

    func fetchIdentity(access: ConnectReadyAccessToken) async throws -> HydratedAccountIdentity {
        fetchCount += 1
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}

private final class SequencingIdentityHydrator: AccountIdentityHydrating, @unchecked Sendable {
    private var results: [Result<HydratedAccountIdentity, DashboardClient.ClientError>]
    private(set) var fetchCount = 0

    init(results: [Result<HydratedAccountIdentity, DashboardClient.ClientError>]) {
        self.results = results
    }

    func fetchIdentity(access: ConnectReadyAccessToken) async throws -> HydratedAccountIdentity {
        fetchCount += 1
        guard !results.isEmpty else { throw DashboardClient.ClientError.decode }
        let next = results.removeFirst()
        switch next {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}

private struct RecordingSleeper: AuthSleeper {
    let onSleep: @Sendable (Int) -> Void
    func sleep(milliseconds: Int) async throws {
        onSleep(milliseconds)
    }
}

private struct NoopSleeper: AuthSleeper {
    func sleep(milliseconds: Int) async throws {}
}

private struct FixedClock: AuthClock {
    let date: Date
    init(_ date: Date) { self.date = date }
    func now() -> Date { date }
}

private struct ThrowingSeatStore: SeatCredentialStore {
    var unreadable: Set<SeatID> = []

    func loadAll() throws -> [StoredSeatRecord] {
        throw SeatKeychainStore.StoreError.accessDenied(-50)
    }

    func load(seatID: SeatID) throws -> StoredSeatRecord? {
        if unreadable.contains(seatID) {
            throw SeatKeychainStore.StoreError.accessDenied(-50)
        }
        return nil
    }

    func save(_ record: StoredSeatRecord) throws {}
    func delete(seatID: SeatID) throws {}
}

private struct FixedEntropy: AuthEntropy {
    let bytes: Data
    let uuid: UUID
    func randomBytes(_ count: Int) -> Data {
        Data(bytes.prefix(count))
    }
    func randomUUID() -> UUID { uuid }
}
