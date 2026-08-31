import CursorBarAdapters
import CursorBarDomain
import Security
import XCTest

final class IDESwitchJournalFailClosedTests: XCTestCase {
    func testHasPendingAccessErrorBlocksSwitchWithoutSecrets() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        journal.configureFailures(hasPending: .accessDenied(errSecAuthFailed))
        let engine = makeJournalEngine(journal: journal)

        let blocked = await engine.beginRequest(seatID: .seat1)
        guard case .failure(.pendingRecoveryOutstanding) = blocked else {
            return XCTFail("expected pendingRecoveryOutstanding, got \(blocked)")
        }
        let phase = await engine.currentPhase()
        guard case .failed(.pendingRecoveryCorrupt) = phase else {
            return XCTFail("expected pendingRecoveryCorrupt, got \(phase)")
        }
        XCTAssertFalse(phase.menuStatusText?.contains("secret") == true)
    }

    func testLoadErrorAtStartupBlocksAndSetsJournalHeld() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        journal.configureFailures(load: .keychain(errSecIO))
        let engine = makeJournalEngine(journal: journal)

        let phase = await engine.bootstrapPendingRecovery()
        guard case .failed(.pendingRecoveryCorrupt) = phase else {
            return XCTFail("expected pendingRecoveryCorrupt, got \(phase)")
        }
        let blocked = await engine.beginRequest(seatID: .seat2)
        guard case .failure(.pendingRecoveryOutstanding) = blocked else {
            return XCTFail("expected blocked switch")
        }
    }

    func testClearErrorAfterInjectFailureBlocksReady() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        journal.configureFailures(clear: .keychain(errSecIO))
        let store = JournalFakeSessionStore()
        store.injectError = .transactionFailed
        let plan = try makeJournalPlan()
        let engine = makeJournalEngine(
            journal: journal,
            store: store,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan))
        )
        _ = await engine.beginRequest(seatID: .seat3)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat3))
        guard case .failed(.pendingRecoveryJournalError(let seatID)) = phase else {
            return XCTFail("expected pendingRecoveryJournalError, got \(phase)")
        }
        XCTAssertEqual(seatID, .seat3)
        let retry = await engine.beginRequest(seatID: .seat4)
        guard case .failure(.pendingRecoveryOutstanding) = retry else {
            return XCTFail("journalHeld must block new switch")
        }
    }

    func testClearErrorAfterRestoreBlocksSwitch() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let backup = AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat1, generation: 1, backup: backup)
        )
        journal.configureFailures(clear: .accessDenied(errSecAuthFailed))
        let store = JournalFakeSessionStore()
        let engine = makeJournalEngine(journal: journal, store: store, pids: [])

        let phase = await engine.bootstrapPendingRecovery()
        guard case .failed(.pendingRecoveryJournalError) = phase else {
            return XCTFail("expected journal clear failure after restore, got \(phase)")
        }
        XCTAssertTrue(try journal.hasPending())
    }

    func testBeginRequestWithLeftoverJournalPromotesVisibleRecovery() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let backup = AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat1, generation: 2, backup: backup)
        )
        let engine = makeJournalEngine(journal: journal)

        let blocked = await engine.beginRequest(seatID: .seat2)
        guard case .failure(.pendingRecoveryOutstanding) = blocked else {
            return XCTFail("expected pendingRecoveryOutstanding, got \(blocked)")
        }
        let phase = await engine.currentPhase()
        guard case .pendingStartupRecovery(let context) = phase else {
            return XCTFail("expected visible pendingStartupRecovery, got \(phase)")
        }
        XCTAssertEqual(context.seatID, .seat1)
        XCTAssertTrue(try journal.hasPending())

        await engine.acknowledge()
        let dismissed = await engine.currentPhase()
        XCTAssertEqual(dismissed, .idle)
        XCTAssertFalse(try journal.hasPending())
        let accepted = await engine.beginRequest(seatID: .seat2)
        guard case .success(.confirming(.seat2)) = accepted else {
            return XCTFail("expected switch after dismiss, got \(accepted)")
        }
    }

    func testRunningCursorDoesNotAutoQuitOnLeftoverJournal() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let backup = AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat1, generation: 2, backup: backup)
        )
        let process = JournalFakeProcess()
        process.pids = [42]
        let store = JournalFakeSessionStore()
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .failure(.refreshFailed)),
            sessionStoreFactory: { store },
            recoveryJournal: journal,
            sharedProfile: SharedCursorProfile.default(homeDirectory: home),
            homeDirectory: home
        )

        let phase = await engine.bootstrapPendingRecovery()
        guard case .pendingStartupRecovery(let context) = phase else {
            return XCTFail("expected pendingStartupRecovery, got \(phase)")
        }
        XCTAssertEqual(context.seatID, .seat1)
        XCTAssertEqual(process.quitCalls, 0)
        XCTAssertTrue(try journal.hasPending())

        await engine.acknowledge()
        let dismissed = await engine.currentPhase()
        XCTAssertEqual(dismissed, .idle)
        XCTAssertFalse(try journal.hasPending())
        let accepted = await engine.beginRequest(seatID: .seat2)
        guard case .success(.confirming(.seat2)) = accepted else {
            return XCTFail("expected switch allowed after dismiss, got \(accepted)")
        }
    }

    func testSuccessfulClearProvesAbsence() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let backup = AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat2, generation: 1, backup: backup)
        )
        let store = JournalFakeSessionStore()
        let engine = makeJournalEngine(journal: journal, store: store, pids: [])

        let phase = await engine.bootstrapPendingRecovery()
        XCTAssertEqual(phase, .idle)
        XCTAssertFalse(try journal.hasPending())
        let accepted = await engine.beginRequest(seatID: .seat5)
        guard case .success(.confirming(.seat5)) = accepted else {
            return XCTFail("expected switch allowed after clear, got \(accepted)")
        }
    }

    func testJournalDuringConfirmLeavesVisibleRecoveryNotStuckConfirming() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let engine = makeJournalEngine(journal: journal)
        let accepted = await engine.beginRequest(seatID: .seat2)
        guard case .success(.confirming(.seat2)) = accepted else {
            return XCTFail("expected confirming, got \(accepted)")
        }
        try journal.save(
            PendingAccountSwitchRecovery(
                seatID: .seat1,
                generation: 4,
                backup: AuthRowBackup(rows: [.accessToken: .present(Data("prior".utf8))])
            )
        )
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat2))
        guard case .pendingStartupRecovery(let context) = phase else {
            return XCTFail("expected visible recovery, got \(phase)")
        }
        XCTAssertEqual(context.seatID, .seat1)
        XCTAssertEqual(context.generation, 4)
    }

    func testPromoteHydratesBackupSoRestoreWritesPriorRows() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let backup = AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat1, generation: 2, backup: backup)
        )
        let store = JournalFakeSessionStore()
        let engine = makeJournalEngine(journal: journal, store: store, pids: [42])
        _ = await engine.beginRequest(seatID: .seat2)
        let phase = await engine.continuePendingRestore()
        XCTAssertEqual(store.restoreCalls, 1)
        XCTAssertEqual(phase, .idle)
    }

    func testJournalClearFailureAfterVerifyDoesNotQuitAgain() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        journal.configureFailures(clear: .keychain(errSecIO))
        let process = JournalFakeProcess()
        process.pids = [42]
        process.waitResults = [true]
        let store = JournalFakeSessionStore()
        let plan = try makeJournalPlan()
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { store },
            recoveryJournal: journal,
            sharedProfile: SharedCursorProfile.default(homeDirectory: home),
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(50),
            recoveryExitWaitTimeout: .milliseconds(50)
        )
        _ = await engine.beginRequest(seatID: .seat3)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat3))
        guard case .failed(.pendingRecoveryJournalError) = phase else {
            return XCTFail("expected journal clear failure, got \(phase)")
        }
        XCTAssertEqual(process.quitCalls, 1)
    }

    func testRestoreRelaunchFailureSurfacesLaunchFailed() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let backup = AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat1, generation: 2, backup: backup)
        )
        let process = JournalFakeProcess()
        process.pids = []
        process.launchError = NSError(domain: "test", code: 9)
        let store = JournalFakeSessionStore()
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .failure(.refreshFailed)),
            sessionStoreFactory: { store },
            recoveryJournal: journal,
            sharedProfile: SharedCursorProfile.default(homeDirectory: home),
            homeDirectory: home
        )
        let phase = await engine.bootstrapPendingRecovery()
        guard case .failed(.launchFailed(let seatID)) = phase else {
            return XCTFail("expected launchFailed after restore, got \(phase)")
        }
        XCTAssertEqual(seatID, .seat1)
        XCTAssertEqual(store.restoreCalls, 1)
        XCTAssertFalse(try journal.hasPending())
    }
}

private func makeJournalPlan(subject: String = "auth0|target") throws -> CursorAuthSessionPlan {
    let accessJWT = journalUnsignedJWT(sub: subject, exp: 1_900_000_000)
    let access = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: accessJWT))
    let refresh = try XCTUnwrap(RefreshToken(journalUnsignedJWT(sub: subject, exp: 1_900_000_000)))
    let material = CursorAuthSessionMaterial(
        access: access,
        refresh: refresh,
        email: Email("switched@example.com"),
        membershipType: "ultra",
        subscriptionStatus: "active"
    )
    switch CursorAuthSessionPlanBuilder.build(from: material) {
    case .success(let plan):
        return plan
    case .failure(let error):
        throw error
    }
}

private func journalUnsignedJWT(sub: String, exp: Int) -> String {
    let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncoded()
    let payload = Data(#"{"sub":"\#(sub)","exp":\#(exp)}"#.utf8).base64URLEncoded()
    return "\(header).\(payload).sig"
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private func makeJournalEngine(
    journal: MemoryAccountSwitchRecoveryJournal,
    store: JournalFakeSessionStore = JournalFakeSessionStore(),
    preparer: FixedAccountSwitchSessionPreparer? = nil,
    pids: [pid_t] = [42]
) -> IDESwitchEngine {
    let process = JournalFakeProcess()
    process.pids = pids
    process.waitResults = [true]
    let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
    return IDESwitchEngine(
        process: process,
        preparer: preparer ?? FixedAccountSwitchSessionPreparer(result: .failure(.refreshFailed)),
        sessionStoreFactory: { store },
        recoveryJournal: journal,
        sharedProfile: SharedCursorProfile.default(homeDirectory: home),
        homeDirectory: home,
        exitWaitTimeout: .milliseconds(50),
        recoveryExitWaitTimeout: .milliseconds(50)
    )
}

private final class JournalFakeProcess: CursorProcessControlling, @unchecked Sendable {
    var pids: [pid_t] = [42]
    var waitResults: [Bool]?
    var waits = 0
    var quitCalls = 0
    var launchError: Error?

    func mainCursorPIDs() -> [pid_t] { pids }
    func argumentListsForMainCursor() -> [[String]] { [] }
    func requestGracefulQuit() -> Bool {
        quitCalls += 1
        return true
    }
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
        if let launchError { throw launchError }
        pids = [99]
    }
    func codeLockExists(in userDataDirectory: URL) -> Bool { false }
}

private final class JournalFakeSessionStore: CursorAuthSessionStoring, @unchecked Sendable {
    var injectError: CursorAuthSessionStore.StoreError?
    var restoreCalls = 0
    var backup = AuthRowBackup(rows: [
        .accessToken: .present(Data("prior-access-secret".utf8)),
        .refreshToken: .present(Data("prior-refresh-secret".utf8)),
    ])
    var identity: CursorIDEIdentity?

    func readBackup(keys: Set<CursorAuthKey>) throws -> AuthRowBackup {
        var rows: [CursorAuthKey: AuthRowPresence] = [:]
        for key in keys {
            rows[key] = backup[key] ?? .absent
        }
        return AuthRowBackup(rows: rows)
    }

    func inject(plan: CursorAuthSessionPlan) throws -> AuthRowBackup {
        if let injectError { throw injectError }
        identity = CursorIDEIdentity(subject: plan.expectedSubject, email: nil)
        return backup
    }

    func restore(_ backup: AuthRowBackup) throws {
        restoreCalls += 1
        _ = backup
        identity = CursorIDEIdentity(subject: "auth0|prior", email: nil)
    }

    func readIdentity() throws -> CursorIDEIdentity? { identity }
}
