import CursorBarAdapters
import CursorBarDomain
import CryptoKit
import SQLite3
import XCTest

final class CursorAuthSessionStoreTests: XCTestCase {
    func testWALInjectionPreservesUnrelatedRowsAndRestoresExactly() throws {
        let fixture = try makeWALFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let beforeUnrelated = try readBlob(dbURL: fixture.dbURL, key: "unrelated/settings")
        let beforeBinary = try readBlob(dbURL: fixture.dbURL, key: "unrelated/binary")
        let beforeOtherTable = try readOtherTableHash(dbURL: fixture.dbURL)
        let beforeAuthAccess = try readBlob(dbURL: fixture.dbURL, key: CursorAuthKey.accessToken.rawValue)
        let beforeTeam = try readBlob(dbURL: fixture.dbURL, key: CursorAuthKey.cachedTeam.rawValue)

        let plan = try makePlan(
            subject: "auth0|next",
            email: "next@example.com",
            membership: "ultra",
            subscription: "active",
            displayName: "Next"
        )
        let store = CursorAuthSessionStore.fixture(
            databaseURL: fixture.dbURL,
            exitGuard: FixedCursorExitGuard(isCursorRunning: false)
        )
        let backup = try store.inject(plan: plan)

        XCTAssertEqual(
            try readBlob(dbURL: fixture.dbURL, key: "unrelated/settings"),
            beforeUnrelated
        )
        XCTAssertEqual(
            try readBlob(dbURL: fixture.dbURL, key: "unrelated/binary"),
            beforeBinary
        )
        XCTAssertEqual(try readOtherTableHash(dbURL: fixture.dbURL), beforeOtherTable)
        XCTAssertEqual(
            try store.readRawValue(for: .accessToken),
            plan.upserts[.accessToken]?.data(using: .utf8)
        )
        XCTAssertEqual(
            try store.readRawValue(for: .stripeMembershipAuthId),
            Data("auth0|next".utf8)
        )
        XCTAssertNil(try store.readRawValue(for: .cachedTeam))
        XCTAssertNil(try store.readRawValue(for: .teamId))
        XCTAssertNil(try store.readRawValue(for: .stripeCustomerId))

        let identity = try XCTUnwrap(try store.readIdentity())
        XCTAssertTrue(CursorIDEIdentity.verify(observed: identity, expectedSubject: "auth0|next"))
        XCTAssertEqual(identity.email?.value, "next@example.com")

        try store.restore(backup)
        XCTAssertEqual(
            try readBlob(dbURL: fixture.dbURL, key: CursorAuthKey.accessToken.rawValue),
            beforeAuthAccess
        )
        XCTAssertEqual(
            try readBlob(dbURL: fixture.dbURL, key: CursorAuthKey.cachedTeam.rawValue),
            beforeTeam
        )
        XCTAssertEqual(
            try readBlob(dbURL: fixture.dbURL, key: "unrelated/settings"),
            beforeUnrelated
        )
        XCTAssertEqual(
            try readBlob(dbURL: fixture.dbURL, key: "unrelated/binary"),
            beforeBinary
        )
        XCTAssertFalse(String(describing: backup).contains("auth0|"))
        XCTAssertFalse(String(describing: plan).contains(plan.upserts[.accessToken]!))
    }

    func testInjectWritesTextAffinitySoCursorStorageReturnsStrings() throws {
        let fixture = try makeWALFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        XCTAssertEqual(
            try readSQLiteType(dbURL: fixture.dbURL, key: CursorAuthKey.accessToken.rawValue),
            "blob"
        )

        let plan = try makePlan(
            subject: "auth0|text",
            email: "text@example.com",
            membership: "ultra",
            subscription: "active",
            displayName: "Text"
        )
        let store = CursorAuthSessionStore.fixture(
            databaseURL: fixture.dbURL,
            exitGuard: FixedCursorExitGuard(isCursorRunning: false)
        )
        _ = try store.inject(plan: plan)

        let textKeys = [
            CursorAuthKey.accessToken.rawValue,
            CursorAuthKey.refreshToken.rawValue,
            CursorAuthKey.cachedEmail.rawValue,
            CursorAuthKey.cachedScopedProfile.rawValue,
            CursorAuthKey.stripeMembershipType.rawValue,
            CursorAuthKey.stripeSubscriptionStatus.rawValue,
            CursorAuthKey.stripeMembershipAuthId.rawValue,
        ]
        for key in textKeys {
            XCTAssertEqual(try readSQLiteType(dbURL: fixture.dbURL, key: key), "text", key)
        }
        XCTAssertEqual(
            try store.readRawValue(for: .accessToken),
            plan.upserts[.accessToken]?.data(using: .utf8)
        )
    }

    func testSparsePlanDeletesOptionalAccountCache() throws {
        let fixture = try makeWALFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let plan = try makePlan(
            subject: "auth0|sparse",
            email: nil,
            membership: nil,
            subscription: nil,
            displayName: nil
        )
        let store = CursorAuthSessionStore.fixture(
            databaseURL: fixture.dbURL,
            exitGuard: FixedCursorExitGuard(isCursorRunning: false)
        )
        _ = try store.inject(plan: plan)
        XCTAssertNil(try store.readRawValue(for: .cachedEmail))
        XCTAssertNil(try store.readRawValue(for: .cachedScopedProfile))
        XCTAssertNil(try store.readRawValue(for: .stripeMembershipType))
        XCTAssertNil(try store.readRawValue(for: .stripeSubscriptionStatus))
        XCTAssertEqual(try store.readRawValue(for: .stripeMembershipAuthId), Data("auth0|sparse".utf8))
    }

    func testCursorRunningGuardLeavesDatabaseUnchanged() throws {
        let fixture = try makeWALFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let before = try fileSHA256(fixture.dbURL)
        let plan = try makePlan(
            subject: "auth0|blocked",
            email: "blocked@example.com",
            membership: "pro",
            subscription: "active",
            displayName: nil
        )
        let store = CursorAuthSessionStore.fixture(
            databaseURL: fixture.dbURL,
            exitGuard: FixedCursorExitGuard(isCursorRunning: true)
        )
        XCTAssertThrowsError(try store.inject(plan: plan)) { error in
            XCTAssertEqual(error as? CursorAuthSessionStore.StoreError, .cursorStillRunning)
        }
        XCTAssertEqual(try fileSHA256(fixture.dbURL), before)
    }

    func testMalformedSchemaFailsClearly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-bar-bad-schema-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbURL = root.appendingPathComponent("state.vscdb")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        try exec(db!, "CREATE TABLE ItemTable (id INTEGER PRIMARY KEY, payload TEXT);")
        sqlite3_close(db)
        db = nil

        let plan = try makePlan(
            subject: "auth0|x",
            email: nil,
            membership: nil,
            subscription: nil,
            displayName: nil
        )
        let store = CursorAuthSessionStore.fixture(
            databaseURL: dbURL,
            exitGuard: FixedCursorExitGuard(isCursorRunning: false)
        )
        XCTAssertThrowsError(try store.inject(plan: plan)) { error in
            XCTAssertEqual(error as? CursorAuthSessionStore.StoreError, .malformedSchema)
        }
    }

    func testLockedDatabaseFailsAndLeavesContentUnchanged() throws {
        let fixture = try makeWALFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let beforeAccess = try readBlob(dbURL: fixture.dbURL, key: CursorAuthKey.accessToken.rawValue)

        var locker: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(fixture.dbURL.path, &locker, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(locker) }
        try exec(locker!, "BEGIN EXCLUSIVE;")

        let plan = try makePlan(
            subject: "auth0|locked",
            email: "locked@example.com",
            membership: "pro",
            subscription: "active",
            displayName: nil
        )
        let store = CursorAuthSessionStore.fixture(
            databaseURL: fixture.dbURL,
            exitGuard: FixedCursorExitGuard(isCursorRunning: false)
        )
        sqlite3_busy_timeout(locker!, 1)
        XCTAssertThrowsError(try store.inject(plan: plan)) { error in
            let storeError = error as? CursorAuthSessionStore.StoreError
            XCTAssertTrue(
                storeError == .databaseBusy || storeError == .transactionFailed,
                "expected busy/failed, got \(String(describing: error))"
            )
        }
        try exec(locker!, "ROLLBACK;")
        XCTAssertEqual(
            try readBlob(dbURL: fixture.dbURL, key: CursorAuthKey.accessToken.rawValue),
            beforeAccess
        )
    }

    func testReadOnlyFailureLeavesDatabaseUnchanged() throws {
        let fixture = try makeWALFixture()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fixture.dbURL.path
            )
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let before = try fileSHA256(fixture.dbURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o400],
            ofItemAtPath: fixture.dbURL.path
        )

        let plan = try makePlan(
            subject: "auth0|readonly",
            email: "ro@example.com",
            membership: "pro",
            subscription: "active",
            displayName: nil
        )
        let store = CursorAuthSessionStore.fixture(
            databaseURL: fixture.dbURL,
            exitGuard: FixedCursorExitGuard(isCursorRunning: false)
        )
        XCTAssertThrowsError(try store.inject(plan: plan))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fixture.dbURL.path
        )
        XCTAssertEqual(try fileSHA256(fixture.dbURL), before)
    }

    func testWrongSubjectVerificationFails() throws {
        let fixture = try makeWALFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = CursorAuthSessionStore.fixture(
            databaseURL: fixture.dbURL,
            exitGuard: FixedCursorExitGuard(isCursorRunning: false)
        )
        let plan = try makePlan(
            subject: "auth0|actual",
            email: "actual@example.com",
            membership: "ultra",
            subscription: "active",
            displayName: nil
        )
        _ = try store.inject(plan: plan)
        let identity = try XCTUnwrap(try store.readIdentity())
        XCTAssertFalse(CursorIDEIdentity.verify(observed: identity, expectedSubject: "auth0|expected"))
        XCTAssertTrue(CursorIDEIdentity.verify(observed: identity, expectedSubject: "auth0|actual"))
    }

    private struct Fixture {
        let root: URL
        let dbURL: URL
    }

    private func makeWALFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-bar-auth-store-\(UUID().uuidString)", isDirectory: true)
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
        try exec(db, "PRAGMA journal_mode=WAL;")
        try exec(
            db,
            """
            CREATE TABLE ItemTable (
              key TEXT UNIQUE ON CONFLICT REPLACE,
              value BLOB
            );
            """
        )
        try exec(db, "CREATE TABLE cursorDiskKV (key TEXT PRIMARY KEY, value BLOB);")
        try insert(db, key: "cursorAuth/accessToken", value: Data(unsignedJWT(sub: "auth0|prior", exp: 1).utf8))
        try insert(db, key: "cursorAuth/refreshToken", value: Data(unsignedJWT(sub: "auth0|prior", exp: 1).utf8))
        try insert(db, key: "cursorAuth/cachedEmail", value: Data("prior@example.com".utf8))
        try insert(db, key: "cursorAuth/cachedScopedProfile", value: Data(#"{"displayName":"Prior"}"#.utf8))
        try insert(db, key: "cursorAuth/stripeMembershipType", value: Data("pro".utf8))
        try insert(db, key: "cursorAuth/stripeSubscriptionStatus", value: Data("active".utf8))
        try insert(db, key: "cursorAuth/stripeMembershipAuthId", value: Data("auth0|prior".utf8))
        try insert(db, key: "cursorAuth/cachedTeam", value: Data(#"{"id":"team-prior"}"#.utf8))
        try insert(db, key: "cursorAuth/teamId", value: Data("team-prior".utf8))
        try insert(db, key: "cursorAuth/stripeCustomerId", value: Data("cus_prior".utf8))
        try insert(db, key: "cursorAuth/onboardingDate", value: Data("2020-01-01".utf8))
        try insert(db, key: "unrelated/settings", value: Data(#"{"theme":"dark","mcp":true}"#.utf8))
        var binary = Data([0x00, 0xFF, 0x10, 0x80])
        binary.append(contentsOf: [UInt8](repeating: 0x42, count: 64))
        try insert(db, key: "unrelated/binary", value: binary)
        try insertOther(db, key: "composer-1", value: Data("keep-me".utf8))
        return Fixture(root: root, dbURL: dbURL)
    }

    private func makePlan(
        subject: String,
        email: String?,
        membership: String?,
        subscription: String?,
        displayName: String?
    ) throws -> CursorAuthSessionPlan {
        let accessJWT = unsignedJWT(sub: subject, exp: 1_900_000_000)
        let access = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: accessJWT))
        let refresh = try XCTUnwrap(RefreshToken(unsignedJWT(sub: subject, exp: 1_900_000_000)))
        let material = CursorAuthSessionMaterial(
            access: access,
            refresh: refresh,
            email: email.flatMap(Email.init),
            displayName: displayName.flatMap(DisplayName.init),
            membershipType: membership,
            subscriptionStatus: subscription,
            scopedProfileJSON: CursorAuthSessionMaterial.scopedProfileJSON(
                displayName: displayName.flatMap(DisplayName.init)
            )
        )
        switch CursorAuthSessionPlanBuilder.build(from: material) {
        case .success(let plan):
            return plan
        case .failure(let error):
            throw error
        }
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            if let error {
                let message = String(cString: error)
                sqlite3_free(error)
                throw NSError(domain: "fixture", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(domain: "fixture", code: 2)
        }
    }

    private func insert(_ db: OpaquePointer, key: String, value: Data) throws {
        var statement: OpaquePointer?
        let sql = "INSERT INTO ItemTable(key, value) VALUES(?, ?);"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw NSError(domain: "fixture", code: 3)
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(statement, 1, key, -1, transient)
        let bind = value.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), transient)
        }
        guard bind == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
            throw NSError(domain: "fixture", code: 4)
        }
    }

    private func insertOther(_ db: OpaquePointer, key: String, value: Data) throws {
        var statement: OpaquePointer?
        let sql = "INSERT INTO cursorDiskKV(key, value) VALUES(?, ?);"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw NSError(domain: "fixture", code: 5)
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(statement, 1, key, -1, transient)
        let bind = value.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), transient)
        }
        guard bind == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
            throw NSError(domain: "fixture", code: 6)
        }
    }

    private func readSQLiteType(dbURL: URL, key: String) throws -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw NSError(domain: "fixture", code: 12)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT typeof(value) FROM ItemTable WHERE key = ? LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw NSError(domain: "fixture", code: 13)
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(statement, 1, key, -1, transient)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW, let typePointer = sqlite3_column_text(statement, 0) else {
            throw NSError(domain: "fixture", code: 14)
        }
        return String(cString: typePointer)
    }

    private func readBlob(dbURL: URL, key: String) throws -> Data? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw NSError(domain: "fixture", code: 7)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw NSError(domain: "fixture", code: 8)
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(statement, 1, key, -1, transient)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW else { throw NSError(domain: "fixture", code: 9) }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, let blob = sqlite3_column_blob(statement, 0) else { return Data() }
        return Data(bytes: blob, count: count)
    }

    private func readOtherTableHash(dbURL: URL) throws -> Data {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw NSError(domain: "fixture", code: 10)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT key, value FROM cursorDiskKV ORDER BY key;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw NSError(domain: "fixture", code: 11)
        }
        defer { sqlite3_finalize(statement) }
        var material = Data()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let keyPointer = sqlite3_column_text(statement, 0) {
                material.append(contentsOf: Array(String(cString: keyPointer).utf8))
            }
            let count = Int(sqlite3_column_bytes(statement, 1))
            if count > 0, let blob = sqlite3_column_blob(statement, 1) {
                material.append(Data(bytes: blob, count: count))
            }
        }
        return Data(SHA256.hash(data: material))
    }

    private func fileSHA256(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        return Data(SHA256.hash(data: data))
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
