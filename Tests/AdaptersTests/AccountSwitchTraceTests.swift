@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class AccountSwitchTraceTests: XCTestCase {
    func testReduceWritesSecretFreeRecords() async throws {
        let tracer = RecordingAccountSwitchTrace()
        let journal = MemoryAccountSwitchRecoveryJournal()
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let engine = IDESwitchEngine(
            process: TraceFakeProcess(),
            preparer: FixedAccountSwitchSessionPreparer(result: .failure(.missingCredentials)),
            sessionStoreFactory: { TraceFakeStore() },
            recoveryJournal: journal,
            tracer: tracer,
            sharedProfile: SharedCursorProfile.default(homeDirectory: home),
            homeDirectory: home
        )
        _ = await engine.beginRequest(seatID: .seat3)
        let records = tracer.snapshot()
        XCTAssertTrue(records.contains(where: { $0.event == "requestOpen:seat3" }))
        XCTAssertTrue(records.contains(where: { $0.to == "confirming:seat3" }))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for record in records {
            let data = try encoder.encode(record)
            let json = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertFalse(json.contains("@"))
            XCTAssertFalse(json.contains("accessToken"))
            XCTAssertFalse(json.contains("refreshToken"))
            XCTAssertFalse(json.contains("Bearer"))
            XCTAssertFalse(json.contains("crsr_"))
        }
    }

    func testFileSinkAppendsJSONL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursorbar-switch-trace-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("account-switch.jsonl")
        let sink = FileAccountSwitchTrace(fileURL: file)
        sink.record(
            AccountSwitchTraceRecord(
                kind: .reduce,
                seat: "seat2",
                from: "idle",
                to: "confirming:seat2",
                event: "requestOpen:seat2"
            )
        )
        sink.record(
            AccountSwitchTraceRecord(
                kind: .reject,
                seat: "seat2",
                from: "pendingStartupRecovery:seat1#1",
                reject: "pendingRecoveryOutstanding",
                journal: "held"
            )
        )
        sink.record(
            AccountSwitchTraceRecord(
                kind: .process,
                seat: "seat3",
                generation: 1,
                from: "quitting:seat3#1",
                note: "quit pids=1 accepted=1"
            )
        )
        let body = try String(contentsOf: file, encoding: .utf8)
        let lines = body.split(whereSeparator: \.isNewline)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(body.contains("\"kind\":\"reduce\""))
        XCTAssertTrue(body.contains("\"kind\":\"process\""))
        XCTAssertTrue(body.contains("pendingRecoveryOutstanding"))
        XCTAssertFalse(body.contains("@"))
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class RecordingAccountSwitchTrace: AccountSwitchTracing, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [AccountSwitchTraceRecord] = []

    func record(_ record: AccountSwitchTraceRecord) {
        lock.lock()
        defer { lock.unlock() }
        records.append(record)
    }

    func snapshot() -> [AccountSwitchTraceRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}

private final class TraceFakeProcess: CursorProcessControlling, @unchecked Sendable {
    func mainCursorPIDs() -> [pid_t] { [1] }
    func argumentListsForMainCursor() -> [[String]] { [] }
    func requestGracefulQuit() -> Bool { true }
    func forceQuit() {}
    func waitUntilMainProcessesExit(timeout: Duration) async -> Bool { true }
    func launch(sharedProfile: SharedCursorProfile, homeDirectory: URL) throws {}
    func codeLockExists(in userDataDirectory: URL) -> Bool { false }
}

private final class TraceFakeStore: CursorAuthSessionStoring, @unchecked Sendable {
    func readBackup(keys: Set<CursorAuthKey>) throws -> AuthRowBackup { AuthRowBackup(rows: [:]) }
    func inject(plan: CursorAuthSessionPlan) throws -> AuthRowBackup { AuthRowBackup(rows: [:]) }
    func restore(_ backup: AuthRowBackup) throws {}
    func readIdentity() throws -> CursorIDEIdentity? { nil }
}
