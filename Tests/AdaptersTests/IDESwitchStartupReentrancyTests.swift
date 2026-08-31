import CursorBarAdapters
import CursorBarDomain
import XCTest

final class IDESwitchStartupReentrancyTests: XCTestCase {
    func testConcurrentBootstrapPendingRecoveryJoinsSingleRestore() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let backup = AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat1, generation: 5, backup: backup)
        )
        let store = ReentrancyFakeSessionStore()
        let process = ReentrancyFakeProcess()
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .failure(.refreshFailed)),
            sessionStoreFactory: { store },
            recoveryJournal: journal,
            sharedProfile: SharedCursorProfile.default(homeDirectory: home),
            homeDirectory: home
        )

        async let first = engine.bootstrapPendingRecovery()
        async let second = engine.bootstrapPendingRecovery()
        let (phaseA, phaseB) = await (first, second)

        XCTAssertEqual(phaseA, phaseB)
        XCTAssertTrue(phaseA.allowsDesktopImport)
        XCTAssertEqual(store.restoreCalls, 1)
        XCTAssertEqual(process.launchCount, 1)
        XCTAssertFalse(try journal.hasPending())
    }

    func testRetryAfterTerminalResetRunsAgain() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        journal.configureFailures(load: .keychain(errSecIO))
        let blockedEngine = makeReentrancyEngine(journal: journal)

        let blocked = await blockedEngine.bootstrapPendingRecovery()
        guard case .failed(.pendingRecoveryCorrupt) = blocked else {
            return XCTFail("expected pendingRecoveryCorrupt, got \(blocked)")
        }

        journal.configureFailures(load: nil)
        let retryEngine = makeReentrancyEngine(journal: journal)
        let cleared = await retryEngine.bootstrapPendingRecovery()
        XCTAssertTrue(cleared.allowsDesktopImport)
    }
}

private func makeReentrancyEngine(journal: MemoryAccountSwitchRecoveryJournal) -> IDESwitchEngine {
    let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
    return IDESwitchEngine(
        process: ReentrancyFakeProcess(),
        preparer: FixedAccountSwitchSessionPreparer(result: .failure(.refreshFailed)),
        sessionStoreFactory: { ReentrancyFakeSessionStore() },
        recoveryJournal: journal,
        sharedProfile: SharedCursorProfile.default(homeDirectory: home),
        homeDirectory: home
    )
}

private final class ReentrancyFakeProcess: CursorProcessControlling, @unchecked Sendable {
    var launchCount = 0

    func mainCursorPIDs() -> [pid_t] { [] }
    func argumentListsForMainCursor() -> [[String]] { [] }
    func requestGracefulQuit() -> Bool { true }
    func forceQuit() {}
    func waitUntilMainProcessesExit(timeout: Duration) async -> Bool { true }
    func launch(sharedProfile: SharedCursorProfile, homeDirectory: URL) throws {
        launchCount += 1
    }
    func codeLockExists(in userDataDirectory: URL) -> Bool { false }
}

private final class ReentrancyFakeSessionStore: CursorAuthSessionStoring, @unchecked Sendable {
    var restoreCalls = 0

    func readBackup(keys: Set<CursorAuthKey>) throws -> AuthRowBackup {
        AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
    }
    func inject(plan: CursorAuthSessionPlan) throws -> AuthRowBackup { try readBackup(keys: []) }
    func restore(_ backup: AuthRowBackup) throws { restoreCalls += 1 }
    func readIdentity() throws -> CursorIDEIdentity? {
        CursorIDEIdentity(subject: "auth0|prior", email: nil)
    }
}
