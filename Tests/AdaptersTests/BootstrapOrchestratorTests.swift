import CursorBarAdapters
import CursorBarDomain
import SQLite3
import XCTest

final class BootstrapOrchestratorTests: XCTestCase {
    func testBootstrapProbesUsageDirectlyWithoutOAuthRefresh() async throws {
        let jwt = unsignedJWT(sub: "bootstrap-user", exp: 2_100_000_000)
        let root = try makeFixtureUserDataDir(
            email: "bootstrap@example.com",
            membership: "ultra",
            accessJWT: jwt,
            refreshJWT: jwt
        )
        defer { try? FileManager.default.removeItem(at: root) }

        nonisolated(unsafe) var paths: [String] = []
        let probe = DashboardSessionProbe { request in
            paths.append(request.url?.path ?? "")
            let json = Data(
                #"""
                {
                  "billingCycleStart": "1700000000000",
                  "billingCycleEnd": "1800000000000",
                  "planUsage": {
                    "autoPercentUsed": 60,
                    "apiPercentUsed": 75,
                    "totalPercentUsed": 69
                  },
                  "displayMessage": "You've used 69% of your included usage"
                }
                """#.utf8
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (json, response)
        }

        let store = UncheckedMemorySeatStore()
        let source = CursorDesktopSessionSource(
            processArgumentsProvider: {
                [["Cursor Helper", "--user-data-dir=\(root.path)"]]
            },
            homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        let orchestrator = BootstrapOrchestrator(
            sessionSource: source,
            keychain: store,
            probe: probe
        )

        let result = try await orchestrator.run()
        XCTAssertFalse(paths.contains(where: { $0.contains("oauth") || $0.contains("token") }))
        XCTAssertEqual(
            paths.filter { $0 == "/aiserver.v1.DashboardService/GetCurrentPeriodUsage" }.count,
            1
        )
        guard case .settled(.imported(.seat1)) = result.phase else {
            return XCTFail("expected imported seat1, got \(result.phase)")
        }
        let seat1 = result.aggregate.seats[0]
        XCTAssertEqual(seat1.email?.value, "bootstrap@example.com")
        XCTAssertEqual(seat1.plan?.name, "ultra")
        XCTAssertEqual(seat1.usage?.totalPercentUsed.percent ?? -1, 69, accuracy: 0.001)
        XCTAssertEqual(seat1.usage?.autoPercentUsed.percent ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(seat1.auth, .signedIn)
    }

    func testProbeFailureDoesNotEraseStoredSeat() async throws {
        let jwt = unsignedJWT(sub: "kept-user", exp: 2_100_000_000)
        let access = try XCTUnwrap(AccessToken(jwt))
        let refresh = try XCTUnwrap(RefreshToken(jwt))
        let stored = StoredSeatRecord(
            seatID: .seat1,
            identity: .subject("kept-user"),
            access: access,
            refresh: refresh,
            email: Email("kept@example.com"),
            expiresAt: Date(timeIntervalSince1970: 2_100_000_000),
            membershipType: "ultra",
            subscriptionStatus: "active"
        )
        let store = UncheckedMemorySeatStore(records: [stored])

        let root = try makeFixtureUserDataDir(
            email: "kept@example.com",
            membership: "ultra",
            accessJWT: jwt,
            refreshJWT: jwt
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let probe = DashboardSessionProbe { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        let source = CursorDesktopSessionSource(
            processArgumentsProvider: {
                [["Cursor Helper", "--user-data-dir=\(root.path)"]]
            },
            homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        let orchestrator = BootstrapOrchestrator(
            sessionSource: source,
            keychain: store,
            probe: probe
        )
        let result = try await orchestrator.run()
        let after = try store.loadAll()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].email?.value, "kept@example.com")
        XCTAssertEqual(result.aggregate.seats[0].email?.value, "kept@example.com")
        guard case .settled(.importFailed) = result.phase else {
            return XCTFail("expected importFailed")
        }
    }

    func testUnboundImportProbeFailureDoesNotAnnotateSeat1OwnedByAnotherIdentity() async throws {
        let seat1JWT = unsignedJWT(sub: "seat1-owner", exp: 2_100_000_000)
        let seat1Access = try XCTUnwrap(AccessToken(seat1JWT))
        let seat1Refresh = try XCTUnwrap(RefreshToken(seat1JWT))
        let stored = StoredSeatRecord(
            seatID: .seat1,
            identity: .subject("seat1-owner"),
            access: seat1Access,
            refresh: seat1Refresh,
            email: Email("seat1@example.com"),
            expiresAt: Date(timeIntervalSince1970: 2_100_000_000),
            membershipType: "ultra",
            subscriptionStatus: "active"
        )
        let store = UncheckedMemorySeatStore(records: [stored])

        let importedJWT = unsignedJWT(sub: "unbound-import", exp: 2_100_000_000)
        let root = try makeFixtureUserDataDir(
            email: "imported@example.com",
            membership: "pro",
            accessJWT: importedJWT,
            refreshJWT: importedJWT
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let probe = DashboardSessionProbe { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        let source = CursorDesktopSessionSource(
            processArgumentsProvider: {
                [["Cursor Helper", "--user-data-dir=\(root.path)"]]
            },
            homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        let orchestrator = BootstrapOrchestrator(
            sessionSource: source,
            keychain: store,
            probe: probe
        )
        let result = try await orchestrator.run()
        guard case .settled(.importFailed(let message)) = result.phase else {
            return XCTFail("expected importFailed, got \(result.phase)")
        }
        XCTAssertTrue(message.contains("401"))
        let seat1 = result.aggregate.seats[0]
        XCTAssertEqual(seat1.email?.value, "seat1@example.com")
        XCTAssertEqual(seat1.auth, .signedIn)
        XCTAssertNil(seat1.authDetail)
        XCTAssertTrue(result.aggregate.seats.allSatisfy { $0.authDetail == nil })
    }

    func testIdempotentSecondRunKeepsSingleSeat() async throws {
        let jwt = unsignedJWT(sub: "idem-user", exp: 2_100_000_000)
        let root = try makeFixtureUserDataDir(
            email: "idem@example.com",
            membership: "pro",
            accessJWT: jwt,
            refreshJWT: jwt
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let probe = DashboardSessionProbe { request in
            let json = Data(
                #"""
                {
                  "billingCycleEnd": "1800000000000",
                  "planUsage": {
                    "autoPercentUsed": 10,
                    "apiPercentUsed": 10,
                    "totalPercentUsed": 10
                  }
                }
                """#.utf8
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (json, response)
        }
        let store = UncheckedMemorySeatStore()
        let source = CursorDesktopSessionSource(
            processArgumentsProvider: {
                [["Cursor Helper", "--user-data-dir=\(root.path)"]]
            },
            homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        let orchestrator = BootstrapOrchestrator(
            sessionSource: source,
            keychain: store,
            probe: probe
        )
        _ = try await orchestrator.run()
        let second = try await orchestrator.run()
        XCTAssertEqual(try store.loadAll().count, 1)
        switch second.phase {
        case .settled(.kept(.seat1)), .settled(.refreshed(.seat1)):
            break
        case .settled(.imported(.seat1)):
            XCTFail("second run should not re-import as new")
        default:
            XCTFail("unexpected \(second.phase)")
        }
    }

    private func makeFixtureUserDataDir(
        email: String,
        membership: String,
        accessJWT: String,
        refreshJWT: String
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-bar-boot-\(UUID().uuidString)", isDirectory: true)
        let globalStorage = root
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("globalStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: globalStorage, withIntermediateDirectories: true)
        let dbURL = globalStorage.appendingPathComponent("state.vscdb")
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, let db else {
            throw NSError(domain: "fixture", code: 1)
        }
        defer { sqlite3_close(db) }
        try exec(db, "CREATE TABLE ItemTable (key TEXT UNIQUE, value BLOB);")
        try insert(db, key: "cursorAuth/accessToken", value: accessJWT)
        try insert(db, key: "cursorAuth/refreshToken", value: refreshJWT)
        try insert(db, key: "cursorAuth/cachedEmail", value: email)
        try insert(db, key: "cursorAuth/stripeMembershipType", value: membership)
        try insert(db, key: "cursorAuth/stripeSubscriptionStatus", value: "active")
        return root
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "fixture", code: 2)
        }
    }

    private func insert(_ db: OpaquePointer, key: String, value: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO ItemTable(key, value) VALUES(?, ?);", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw NSError(domain: "fixture", code: 3)
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(statement, 1, key, -1, transient)
        _ = sqlite3_bind_text(statement, 2, value, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NSError(domain: "fixture", code: 4)
        }
    }

    private func unsignedJWT(sub: String, exp: Int) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URL()
        let payload = Data(#"{"sub":"\#(sub)","exp":\#(exp)}"#.utf8).base64URL()
        return "\(header).\(payload).sig"
    }
}

private extension Data {
    func base64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
