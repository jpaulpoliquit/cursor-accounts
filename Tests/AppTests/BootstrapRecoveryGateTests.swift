import CursorBarAdapters
import CursorBarDomain
import XCTest

@MainActor
final class BootstrapRecoveryGateTests: XCTestCase {
    func testBootstrapStartsAfterNoJournalRecovery() async throws {
        nonisolated(unsafe) var bootstrapRuns = 0
        let session = BootstrapSession(shell: .empty) {
            bootstrapRuns += 1
            return BootstrapOrchestrator.Result(
                phase: .settled(.noDesktopSession),
                aggregate: .empty
            )
        }
        let journal = MemoryAccountSwitchRecoveryJournal()
        let engine = makeGateEngine(journal: journal, pids: [])
        let model = GateHarness(session: session, engine: engine)

        await model.awaitStartupRecovery()
        let phase = await engine.currentPhase()
        XCTAssertTrue(phase.allowsDesktopImport)

        await model.startBootstrapIfAllowed()
        await waitUntil { bootstrapRuns == 1 }
        XCTAssertEqual(bootstrapRuns, 1)
    }

    func testBootstrapBlockedWhileRecoveryJournalUnresolved() async throws {
        nonisolated(unsafe) var bootstrapRuns = 0
        let session = BootstrapSession(shell: .empty) {
            bootstrapRuns += 1
            return BootstrapOrchestrator.Result(
                phase: .settled(.noDesktopSession),
                aggregate: .empty
            )
        }
        let journal = MemoryAccountSwitchRecoveryJournal()
        let backup = AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat2, generation: 2, backup: backup)
        )
        let process = GateFakeProcess()
        process.pids = [77]
        process.waitResults = [false]
        let engine = makeGateEngine(journal: journal, process: process)

        let model = GateHarness(session: session, engine: engine)
        await model.awaitStartupRecovery()
        let phase = await engine.currentPhase()
        XCTAssertFalse(phase.allowsDesktopImport)
        await model.startBootstrapIfAllowed()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(bootstrapRuns, 0)
    }

    func testBootstrapObservesRestoredStateAfterJournalRecovery() async throws {
        nonisolated(unsafe) var bootstrapRuns = 0
        let session = BootstrapSession(shell: .empty) {
            bootstrapRuns += 1
            return BootstrapOrchestrator.Result(
                phase: .settled(.noDesktopSession),
                aggregate: .empty
            )
        }
        let journal = MemoryAccountSwitchRecoveryJournal()
        let backup = AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat1, generation: 1, backup: backup)
        )
        let engine = makeGateEngine(journal: journal, pids: [])
        let model = GateHarness(session: session, engine: engine)

        await model.awaitStartupRecovery()
        let phase = await engine.currentPhase()
        XCTAssertTrue(phase.allowsDesktopImport)
        await model.startBootstrapIfAllowed()
        await waitUntil { bootstrapRuns == 1 }
        XCTAssertFalse(try journal.hasPending())
    }

    func testAcknowledgeUnblocksDesktopImport() async throws {
        nonisolated(unsafe) var bootstrapRuns = 0
        let session = BootstrapSession(shell: .empty) {
            bootstrapRuns += 1
            return BootstrapOrchestrator.Result(
                phase: .settled(.noDesktopSession),
                aggregate: .empty
            )
        }
        let journal = MemoryAccountSwitchRecoveryJournal()
        let backup = AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat2, generation: 2, backup: backup)
        )
        let process = GateFakeProcess()
        process.pids = [77]
        let engine = makeGateEngine(journal: journal, process: process)
        let model = GateHarness(session: session, engine: engine)

        await model.awaitStartupRecovery()
        let blocked = await engine.currentPhase()
        XCTAssertFalse(blocked.allowsDesktopImport)
        await engine.acknowledge()
        let dismissed = await engine.currentPhase()
        XCTAssertTrue(dismissed.allowsDesktopImport)
        XCTAssertFalse(try journal.hasPending())
        await model.startBootstrapIfAllowed()
        await waitUntil { bootstrapRuns == 1 }
    }
}

@MainActor
private final class GateHarness {
    private let session: BootstrapSession
    private let engine: IDESwitchEngine
    private var recoveryTask: Task<Void, Never>?

    init(session: BootstrapSession, engine: IDESwitchEngine) {
        self.session = session
        self.engine = engine
    }

    func awaitStartupRecovery() async {
        if let recoveryTask {
            await recoveryTask.value
            return
        }
        let task = Task {
            _ = await self.engine.bootstrapPendingRecovery()
        }
        recoveryTask = task
        await task.value
        recoveryTask = nil
    }

    func startBootstrapIfAllowed() async {
        let phase = await engine.currentPhase()
        guard phase.allowsDesktopImport else { return }
        session.ensureStarted()
    }
}

private func makeGateEngine(
    journal: MemoryAccountSwitchRecoveryJournal,
    pids: [pid_t] = []
) -> IDESwitchEngine {
    let process = GateFakeProcess()
    process.pids = pids
    return makeGateEngine(journal: journal, process: process)
}

private func makeGateEngine(
    journal: MemoryAccountSwitchRecoveryJournal,
    process: GateFakeProcess
) -> IDESwitchEngine {
    let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
    return IDESwitchEngine(
        process: process,
        preparer: FixedAccountSwitchSessionPreparer(result: .failure(.refreshFailed)),
        sessionStoreFactory: { GateFakeSessionStore() },
        recoveryJournal: journal,
        sharedProfile: SharedCursorProfile.default(homeDirectory: home),
        homeDirectory: home,
        recoveryExitWaitTimeout: .milliseconds(20)
    )
}

private final class GateFakeProcess: CursorProcessControlling, @unchecked Sendable {
    var pids: [pid_t] = []
    var waitResults: [Bool]?
    var waits = 0
    var restoreLaunchCount = 0

    func mainCursorPIDs() -> [pid_t] { pids }
    func argumentListsForMainCursor() -> [[String]] { [] }
    func requestGracefulQuit() -> Bool { true }
    func forceQuit() { pids = [] }
    func waitUntilMainProcessesExit(timeout: Duration) async -> Bool {
        waits += 1
        if let waitResults {
            let index = waits - 1
            let result = index < waitResults.count ? waitResults[index] : waitResults.last ?? false
            if result { pids = [] }
            return result
        }
        pids = []
        return true
    }
    func launch(sharedProfile: SharedCursorProfile, homeDirectory: URL) throws {
        restoreLaunchCount += 1
        pids = [1]
    }
    func codeLockExists(in userDataDirectory: URL) -> Bool { false }
}

private final class GateFakeSessionStore: CursorAuthSessionStoring, @unchecked Sendable {
    func readBackup(keys: Set<CursorAuthKey>) throws -> AuthRowBackup {
        AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
    }
    func inject(plan: CursorAuthSessionPlan) throws -> AuthRowBackup { try readBackup(keys: []) }
    func restore(_ backup: AuthRowBackup) throws {}
    func readIdentity() throws -> CursorIDEIdentity? {
        CursorIDEIdentity(subject: "auth0|prior", email: nil)
    }
}

@MainActor
private func waitUntil(_ predicate: () -> Bool, timeoutMs: Int = 3000) async {
    let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
    while ContinuousClock.now < deadline {
        if predicate() { return }
        await Task.yield()
    }
    XCTFail("waitUntil timed out")
}
