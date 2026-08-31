import CursorBarAdapters
import CursorBarDomain
import SQLite3
import XCTest

final class SQLiteSessionReaderTests: XCTestCase {
    func testReadsExactAuthKeysFromFixtureDatabase() throws {
        let root = try makeFixtureUserDataDir(
            email: "fixture@example.com",
            membership: "ultra",
            accessJWT: unsignedJWT(sub: "fixture-sub", exp: 1_800_000_000),
            refreshJWT: unsignedJWT(sub: "fixture-sub", exp: 1_800_000_000)
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let source = CursorDesktopSessionSource(
            processArgumentsProvider: {
                [["Cursor Helper", "--user-data-dir=\(root.path)"]]
            },
            homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        let session = try XCTUnwrap(try source.load())
        XCTAssertEqual(session.email?.value, "fixture@example.com")
        XCTAssertEqual(session.membershipType, "ultra")
        XCTAssertEqual(session.identity, .subject("fixture-sub"))
        XCTAssertEqual(session.claims.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertFalse(String(describing: session).contains(session.access.rawValue))
    }

    private func makeFixtureUserDataDir(
        email: String,
        membership: String,
        accessJWT: String,
        refreshJWT: String
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-bar-fixture-\(UUID().uuidString)", isDirectory: true)
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
        try insert(db, key: "unrelated/huge", value: String(repeating: "x", count: 1024))
        return root
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            throw NSError(domain: "fixture", code: 2)
        }
    }

    private func insert(_ db: OpaquePointer, key: String, value: String) throws {
        var statement: OpaquePointer?
        let sql = "INSERT INTO ItemTable(key, value) VALUES(?, ?);"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
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
