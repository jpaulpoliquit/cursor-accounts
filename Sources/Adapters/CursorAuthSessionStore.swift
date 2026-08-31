import CursorBarDomain
import Foundation
import SQLite3

/// Exclusive row-level auth inject/restore for a caller-provided `state.vscdb` URL.
/// Never hardcodes the live Cursor path. Durable recovery journals live in CursorBar Keychain.
public struct CursorAuthSessionStore: Sendable {
    public enum StoreError: Error, Sendable, Equatable {
        case cursorStillRunning
        case databaseUnavailable
        case databaseBusy
        case malformedSchema
        case transactionFailed
        case restoreFailed
        case liveDatabaseBlocked
    }

    /// Tests must use `.fixturesOnly` so accidental live Cursor DB paths are refused.
    public enum OpenPolicy: Sendable, Equatable {
        case production
        case fixturesOnly
    }

    private let databaseURL: URL
    private let exitGuard: any CursorExitGuarding
    private let openPolicy: OpenPolicy

    public init(
        databaseURL: URL,
        exitGuard: any CursorExitGuarding,
        openPolicy: OpenPolicy = .production
    ) {
        self.databaseURL = databaseURL
        self.exitGuard = exitGuard
        self.openPolicy = openPolicy
    }

    public static func forSharedProfile(
        _ profile: SharedCursorProfile,
        exitGuard: any CursorExitGuarding
    ) -> CursorAuthSessionStore {
        CursorAuthSessionStore(
            databaseURL: profile.stateDatabaseURL,
            exitGuard: exitGuard,
            openPolicy: .production
        )
    }

    public static func fixture(
        databaseURL: URL,
        exitGuard: any CursorExitGuarding
    ) -> CursorAuthSessionStore {
        CursorAuthSessionStore(
            databaseURL: databaseURL,
            exitGuard: exitGuard,
            openPolicy: .fixturesOnly
        )
    }

    public func readBackup(keys: Set<CursorAuthKey>) throws -> AuthRowBackup {
        try withReadableDatabase { db in
            try readBackup(db: db, keys: keys)
        }
    }

    /// Atomically upserts/deletes plan keys. Returns backup of affected keys only.
    /// Callers that need crash safety must persist a journal from `readBackup` before this mutates.
    public func inject(plan: CursorAuthSessionPlan) throws -> AuthRowBackup {
        try withWritableDatabase { db in
            try exec(db, "BEGIN IMMEDIATE;")
            do {
                let backup = try readBackup(db: db, keys: plan.affectedKeys)
                for key in plan.deletes.sorted(by: { $0.rawValue < $1.rawValue }) {
                    try deleteRow(db: db, key: key)
                }
                for key in plan.upserts.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                    guard let value = plan.upserts[key], let data = value.data(using: .utf8) else {
                        throw StoreError.transactionFailed
                    }
                    try upsertRow(db: db, key: key, value: data)
                }
                try exec(db, "COMMIT;")
                return backup
            } catch {
                _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw mapWriteError(error)
            }
        }
    }

    /// Restores exact prior presence/value for every key in the backup.
    public func restore(_ backup: AuthRowBackup) throws {
        try withWritableDatabase { db in
            try exec(db, "BEGIN IMMEDIATE;")
            do {
                for key in backup.rows.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                    guard let presence = backup.rows[key] else { continue }
                    switch presence {
                    case .absent:
                        try deleteRow(db: db, key: key)
                    case .present(let data):
                        try upsertRow(db: db, key: key, value: data)
                    }
                }
                try exec(db, "COMMIT;")
            } catch {
                _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw StoreError.restoreFailed
            }
        }
    }

    /// Read-only identity snapshot from access JWT + cached email.
    public func readIdentity() throws -> CursorIDEIdentity? {
        try withReadableDatabase { db in
            let access = try readUTF8(db: db, key: .accessToken)
            let email = try readUTF8(db: db, key: .cachedEmail)
            guard let access else { return nil }
            return CursorIDEIdentity.from(accessTokenJWT: access, cachedEmail: email)
        }
    }

    /// Test helper: raw blob for one auth key (nil when absent).
    public func readRawValue(for key: CursorAuthKey) throws -> Data? {
        try withReadableDatabase { db in
            try readBlob(db: db, key: key.itemTableKey)
        }
    }

    private func withWritableDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try assertOpenPolicyAllowsURL()
        if exitGuard.isCursorRunning {
            throw StoreError.cursorStillRunning
        }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(databaseURL.path, &db, flags, nil)
        guard openResult == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            if openResult == SQLITE_BUSY || openResult == SQLITE_LOCKED {
                throw StoreError.databaseBusy
            }
            throw StoreError.databaseUnavailable
        }
        defer { sqlite3_close(db) }
        try validateItemTableSchema(db)
        do {
            return try body(db)
        } catch let error as StoreError {
            throw error
        } catch {
            throw mapWriteError(error)
        }
    }

    private func withReadableDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try assertOpenPolicyAllowsURL()
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(databaseURL.path, &db, flags, nil)
        guard openResult == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            if openResult == SQLITE_BUSY || openResult == SQLITE_LOCKED {
                throw StoreError.databaseBusy
            }
            throw StoreError.databaseUnavailable
        }
        defer { sqlite3_close(db) }
        try validateItemTableSchema(db)
        return try body(db)
    }

    private func validateItemTableSchema(_ db: OpaquePointer) throws {
        var statement: OpaquePointer?
        let sql = "PRAGMA table_info(ItemTable);"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.malformedSchema
        }
        defer { sqlite3_finalize(statement) }

        var columns: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let namePointer = sqlite3_column_text(statement, 1),
                  let typePointer = sqlite3_column_text(statement, 2)
            else {
                continue
            }
            let name = String(cString: namePointer)
            let type = String(cString: typePointer).uppercased()
            columns[name] = type
        }
        guard columns["key"] != nil, columns["value"] != nil else {
            throw StoreError.malformedSchema
        }
    }

    private func readBackup(db: OpaquePointer, keys: Set<CursorAuthKey>) throws -> AuthRowBackup {
        var rows: [CursorAuthKey: AuthRowPresence] = [:]
        for key in keys {
            if let data = try readBlob(db: db, key: key.itemTableKey) {
                rows[key] = .present(data)
            } else {
                rows[key] = .absent
            }
        }
        return AuthRowBackup(rows: rows)
    }

    private func readUTF8(db: OpaquePointer, key: CursorAuthKey) throws -> String? {
        guard let data = try readBlob(db: db, key: key.itemTableKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func readBlob(db: OpaquePointer, key: String) throws -> Data? {
        var statement: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.transactionFailed
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(statement, 1, key, -1, transient)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE {
            return nil
        }
        guard step == SQLITE_ROW else {
            if step == SQLITE_BUSY || step == SQLITE_LOCKED {
                throw StoreError.databaseBusy
            }
            throw StoreError.transactionFailed
        }
        let byteCount = Int(sqlite3_column_bytes(statement, 0))
        guard byteCount > 0, let blob = sqlite3_column_blob(statement, 0) else {
            return Data()
        }
        return Data(bytes: blob, count: byteCount)
    }

    private func upsertRow(db: OpaquePointer, key: CursorAuthKey, value: Data) throws {
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO ItemTable(key, value) VALUES(?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.transactionFailed
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(statement, 1, key.itemTableKey, -1, transient)
        // Cursor's JS storage returns BLOBs as Buffer. getAccessToken then calls `.split`.
        let bindResult = value.withUnsafeBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return sqlite3_bind_text(statement, 2, "", 0, transient)
            }
            return sqlite3_bind_text(statement, 2, base, Int32(buffer.count), transient)
        }
        guard bindResult == SQLITE_OK else { throw StoreError.transactionFailed }
        let step = sqlite3_step(statement)
        guard step == SQLITE_DONE else {
            if step == SQLITE_BUSY || step == SQLITE_LOCKED {
                throw StoreError.databaseBusy
            }
            throw StoreError.transactionFailed
        }
    }

    private func deleteRow(db: OpaquePointer, key: CursorAuthKey) throws {
        var statement: OpaquePointer?
        let sql = "DELETE FROM ItemTable WHERE key = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.transactionFailed
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(statement, 1, key.itemTableKey, -1, transient)
        let step = sqlite3_step(statement)
        guard step == SQLITE_DONE else {
            if step == SQLITE_BUSY || step == SQLITE_LOCKED {
                throw StoreError.databaseBusy
            }
            throw StoreError.transactionFailed
        }
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if let errorMessage {
            sqlite3_free(errorMessage)
        }
        guard result == SQLITE_OK else {
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                throw StoreError.databaseBusy
            }
            throw StoreError.transactionFailed
        }
    }

    private func mapWriteError(_ error: Error) -> StoreError {
        if let storeError = error as? StoreError {
            return storeError
        }
        return .transactionFailed
    }

    private func assertOpenPolicyAllowsURL() throws {
        guard openPolicy == .fixturesOnly else { return }
        let path = databaseURL.standardizedFileURL.path
        let marker = "/Library/Application Support/Cursor/"
        if path.contains(marker) {
            throw StoreError.liveDatabaseBlocked
        }
    }
}

extension CursorAuthSessionStore.StoreError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cursorStillRunning: "CursorAuthSessionStore.cursorStillRunning"
        case .databaseUnavailable: "CursorAuthSessionStore.databaseUnavailable"
        case .databaseBusy: "CursorAuthSessionStore.databaseBusy"
        case .malformedSchema: "CursorAuthSessionStore.malformedSchema"
        case .transactionFailed: "CursorAuthSessionStore.transactionFailed"
        case .restoreFailed: "CursorAuthSessionStore.restoreFailed"
        case .liveDatabaseBlocked: "CursorAuthSessionStore.liveDatabaseBlocked"
        }
    }
}
