import CursorBarAdapters
import CursorBarDomain
import Foundation
import XCTest

private final class FakeCursorProcess: CursorProcessControlling, @unchecked Sendable {
    var pids: [pid_t] = [42]
    var argumentLists: [[String]] = [["/Applications/Cursor.app/Contents/MacOS/Cursor"]]
    var quitCalls = 0
    var forceQuitCalls = 0
    var launchProfiles: [SharedCursorProfile] = []
    var exitAfterWaits = 1
    var waits = 0
    /// When set, the Nth wait (1-based) returns this value and optionally clears PIDs.
    var waitResults: [Bool]?
    var codeLockDirectories: Set<String> = []
    var launchError: Error?
    var clearPIDsOnLaunch = false

    func mainCursorPIDs() -> [pid_t] { pids }
    func argumentListsForMainCursor() -> [[String]] { argumentLists }
    func requestGracefulQuit() -> Bool {
        quitCalls += 1
        return true
    }
    var forceQuitClearsPIDs = true

    func forceQuit() {
        forceQuitCalls += 1
        if forceQuitClearsPIDs { pids = [] }
    }
    func waitUntilMainProcessesExit(timeout: Duration) async -> Bool {
        waits += 1
        if let waitResults {
            let index = waits - 1
            let result = index < waitResults.count ? waitResults[index] : waitResults.last ?? false
            if result { pids = [] }
            return result
        }
        if waits >= exitAfterWaits {
            pids = []
            return true
        }
        return false
    }
    func launch(sharedProfile: SharedCursorProfile, homeDirectory: URL) throws {
        if let launchError { throw launchError }
        launchProfiles.append(sharedProfile)
        if clearPIDsOnLaunch {
            pids = []
        } else {
            pids = [99]
        }
        let args = CursorLaunchArguments.sharedProfileArguments(
            for: sharedProfile,
            homeDirectory: homeDirectory
        )
        argumentLists = [["/Applications/Cursor.app/Contents/MacOS/Cursor"] + args]
    }
    func codeLockExists(in userDataDirectory: URL) -> Bool {
        codeLockDirectories.contains(userDataDirectory.path)
    }
}

private final class StickyWrongStore: CursorAuthSessionStoring, @unchecked Sendable {
    let inner: FakeSessionStore
    init(inner: FakeSessionStore) { self.inner = inner }
    func readBackup(keys: Set<CursorAuthKey>) throws -> AuthRowBackup {
        try inner.readBackup(keys: keys)
    }
    func inject(plan: CursorAuthSessionPlan) throws -> AuthRowBackup {
        let backup = try inner.inject(plan: plan)
        inner.identity = CursorIDEIdentity(subject: "auth0|wrong", email: nil)
        return backup
    }
    func restore(_ backup: AuthRowBackup) throws { try inner.restore(backup) }
    func readIdentity() throws -> CursorIDEIdentity? { try inner.readIdentity() }
}

private final class FakeSessionStore: CursorAuthSessionStoring, @unchecked Sendable {
    var identity: CursorIDEIdentity?
    var injectError: CursorAuthSessionStore.StoreError?
    var restoreError: CursorAuthSessionStore.StoreError?
    var injectCalls = 0
    var restoreCalls = 0
    var readBackupCalls = 0
    var lastPlan: CursorAuthSessionPlan?
    var backup = AuthRowBackup(rows: [
        .accessToken: .present(Data("prior-access-secret".utf8)),
        .refreshToken: .present(Data("prior-refresh-secret".utf8)),
        .cachedEmail: .absent,
    ])
    var injectedSubjects: [String] = []

    func readBackup(keys: Set<CursorAuthKey>) throws -> AuthRowBackup {
        readBackupCalls += 1
        var rows: [CursorAuthKey: AuthRowPresence] = [:]
        for key in keys {
            rows[key] = backup[key] ?? .absent
        }
        return AuthRowBackup(rows: rows)
    }

    func inject(plan: CursorAuthSessionPlan) throws -> AuthRowBackup {
        injectCalls += 1
        lastPlan = plan
        if let injectError { throw injectError }
        injectedSubjects.append(plan.expectedSubject)
        identity = CursorIDEIdentity(subject: plan.expectedSubject, email: Email("switched@example.com"))
        return backup
    }

    func restore(_ backup: AuthRowBackup) throws {
        restoreCalls += 1
        _ = backup
        if let restoreError { throw restoreError }
        identity = CursorIDEIdentity(subject: "auth0|prior", email: Email("prior@example.com"))
    }

    func readIdentity() throws -> CursorIDEIdentity? {
        identity
    }
}

final class IDESwitchEngineTests: XCTestCase {
    func testHappyPathPreflightInjectSharedLaunchVerify() async throws {
        let process = FakeCursorProcess()
        process.exitAfterWaits = 1
        let store = FakeSessionStore()
        let plan = try makePlan(subject: "auth0|target")
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorBarSwitchHappy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let profile = SharedCursorProfile.default(homeDirectory: home)

        let journal = MemoryAccountSwitchRecoveryJournal()
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { store },
            recoveryJournal: journal,
            sharedProfile: profile,
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(50),
            verifyTimeout: .milliseconds(200)
        )
        _ = await engine.beginRequest(seatID: .seat2)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat2))
        XCTAssertEqual(phase, .ready(.seat2))
        XCTAssertEqual(store.injectCalls, 1)
        XCTAssertEqual(store.restoreCalls, 0)
        XCTAssertEqual(process.quitCalls, 1)
        XCTAssertEqual(process.forceQuitCalls, 0)
        XCTAssertEqual(process.launchProfiles, [profile])
        XCTAssertFalse(try journal.hasPending())
        let launchPlan = CursorLaunchPlan(
            executableURL: CursorProcessAdapter.defaultCursorExecutable,
            sharedProfile: profile,
            homeDirectory: home
        )
        XCTAssertEqual(launchPlan.arguments, [])
        XCTAssertFalse(launchPlan.arguments.contains { $0.contains("seat-") })
        XCTAssertFalse(launchPlan.arguments.contains { $0.localizedCaseInsensitiveContains("token") })
    }

    func testPreflightFailureLeavesProcessRunningAndSkipsInject() async throws {
        let process = FakeCursorProcess()
        process.pids = [7]
        let store = FakeSessionStore()
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .failure(.refreshFailed)),
            sessionStoreFactory: { store },
            recoveryJournal: MemoryAccountSwitchRecoveryJournal(),
            sharedProfile: SharedCursorProfile.default(homeDirectory: home),
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(20)
        )
        _ = await engine.beginRequest(seatID: .seat1)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat1))
        guard case .failed(.preflightFailed(let seatID, .refreshFailed)) = phase else {
            return XCTFail("expected preflightFailed, got \(phase)")
        }
        XCTAssertEqual(seatID, .seat1)
        XCTAssertEqual(process.quitCalls, 0)
        XCTAssertEqual(store.injectCalls, 0)
        XCTAssertEqual(process.pids, [7])
        XCTAssertFalse(phase.allowsForceQuit)
    }

    func testCursorRunningGuardMapsToDBBusy() async throws {
        let process = FakeCursorProcess()
        process.exitAfterWaits = 1
        let store = FakeSessionStore()
        store.injectError = .cursorStillRunning
        let plan = try makePlan(subject: "auth0|busy")
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { store },
            recoveryJournal: MemoryAccountSwitchRecoveryJournal(),
            sharedProfile: SharedCursorProfile.default(homeDirectory: home),
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(50)
        )
        _ = await engine.beginRequest(seatID: .seat3)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat3))
        guard case .failed(.dbBusyOrLocked(let seatID)) = phase else {
            return XCTFail("expected dbBusyOrLocked, got \(phase)")
        }
        XCTAssertEqual(seatID, .seat3)
        XCTAssertTrue(process.launchProfiles.isEmpty)
        XCTAssertFalse(phase.allowsForceQuit)
    }

    func testTimeoutDoesNotAutoForceQuit() async {
        let process = FakeCursorProcess()
        process.exitAfterWaits = 100
        let store = FakeSessionStore()
        let plan = try! makePlan(subject: "auth0|timeout")
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { store },
            recoveryJournal: MemoryAccountSwitchRecoveryJournal(),
            sharedProfile: SharedCursorProfile.default(homeDirectory: home),
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(20)
        )
        _ = await engine.beginRequest(seatID: .seat1)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat1))
        guard case .failed(.quitTimedOut(let seatID)) = phase else {
            return XCTFail("expected quitTimedOut, got \(phase)")
        }
        XCTAssertEqual(seatID, .seat1)
        XCTAssertTrue(phase.allowsForceQuit)
        XCTAssertEqual(phase.forceQuitPrompt, .continueAccountSwitch)
        XCTAssertEqual(process.forceQuitCalls, 0)
        XCTAssertEqual(store.injectCalls, 0)
        XCTAssertTrue(process.launchProfiles.isEmpty)
    }

    func testForceQuitFailedKeepsContextForRetry() async throws {
        let process = FakeCursorProcess()
        process.exitAfterWaits = 100
        process.forceQuitClearsPIDs = false
        let store = FakeSessionStore()
        let plan = try makePlan(subject: "auth0|retry")
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorBarForceQuitRetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let profile = SharedCursorProfile.default(homeDirectory: home)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { store },
            recoveryJournal: MemoryAccountSwitchRecoveryJournal(),
            sharedProfile: profile,
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(20),
            forceQuitWaitTimeout: .milliseconds(20)
        )
        _ = await engine.beginRequest(seatID: .seat3)
        let timedOut = await engine.runConfirmed(.confirmed(seatID: .seat3))
        guard case .failed(.quitTimedOut) = timedOut else {
            return XCTFail("expected quitTimedOut, got \(timedOut)")
        }

        process.waitResults = [false]
        let first = await engine.forceQuitAfterTimeout()
        guard case .failed(.forceQuitFailed(let seatID)) = first else {
            return XCTFail("expected forceQuitFailed, got \(first)")
        }
        XCTAssertEqual(seatID, .seat3)
        XCTAssertTrue(first.allowsForceQuit)
        XCTAssertEqual(store.injectCalls, 0)

        process.forceQuitClearsPIDs = true
        process.waitResults = [true]
        process.waits = 0
        let retried = await engine.forceQuitAfterTimeout()
        XCTAssertEqual(retried, .ready(.seat3))
        XCTAssertEqual(process.forceQuitCalls, 2)
        XCTAssertEqual(store.injectCalls, 1)
    }

    func testLaunchFailureRestoresBackup() async throws {
        let process = FakeCursorProcess()
        process.exitAfterWaits = 1
        process.launchError = NSError(domain: "test", code: 1)
        let store = FakeSessionStore()
        let plan = try makePlan(subject: "auth0|launch")
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { store },
            recoveryJournal: MemoryAccountSwitchRecoveryJournal(),
            sharedProfile: SharedCursorProfile.default(homeDirectory: home),
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(50)
        )
        _ = await engine.beginRequest(seatID: .seat2)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat2))
        guard case .failed(.launchFailed(let seatID)) = phase else {
            return XCTFail("expected launchFailed, got \(phase)")
        }
        XCTAssertEqual(seatID, .seat2)
        XCTAssertEqual(store.injectCalls, 1)
        XCTAssertEqual(store.restoreCalls, 1)
        XCTAssertEqual(process.forceQuitCalls, 0)
        XCTAssertFalse(phase.allowsForceQuit)
    }

    func testVerificationMismatchGracefulQuitRestoresWithoutForceQuit() async throws {
        let process = FakeCursorProcess()
        // First wait: initial switch exit. Second wait: recovery quit succeeds.
        process.waitResults = [true, true]
        let store = FakeSessionStore()
        let plan = try makePlan(subject: "auth0|expected")
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorBarVerifyFail-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let profile = SharedCursorProfile.default(homeDirectory: home)

        let sticky = StickyWrongStore(inner: store)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { sticky },
            recoveryJournal: MemoryAccountSwitchRecoveryJournal(),
            sharedProfile: profile,
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(50),
            verifyTimeout: .milliseconds(100),
            recoveryExitWaitTimeout: .milliseconds(50)
        )
        _ = await engine.beginRequest(seatID: .seat4)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat4))
        guard case .failed(.verificationFailed(let seatID)) = phase else {
            return XCTFail("expected verificationFailed, got \(phase)")
        }
        XCTAssertEqual(seatID, .seat4)
        XCTAssertEqual(store.restoreCalls, 1)
        XCTAssertEqual(process.forceQuitCalls, 0)
        XCTAssertGreaterThanOrEqual(process.quitCalls, 2)
        XCTAssertGreaterThanOrEqual(process.launchProfiles.count, 2)
    }

    func testVerificationMismatchRecoveryQuitTimeoutNeedsExplicitForceQuit() async throws {
        let process = FakeCursorProcess()
        // Initial exit succeeds; recovery quit times out.
        process.waitResults = [true, false]
        let store = FakeSessionStore()
        let plan = try makePlan(subject: "auth0|expected")
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorBarRecoverTimeout-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let profile = SharedCursorProfile.default(homeDirectory: home)
        let sticky = StickyWrongStore(inner: store)
        let journal = MemoryAccountSwitchRecoveryJournal()

        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { sticky },
            recoveryJournal: journal,
            sharedProfile: profile,
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(50),
            verifyTimeout: .milliseconds(80),
            recoveryExitWaitTimeout: .milliseconds(30)
        )
        _ = await engine.beginRequest(seatID: .seat5)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat5))
        guard case .failed(.recoveryQuitTimedOut(let context)) = phase else {
            return XCTFail("expected recoveryQuitTimedOut, got \(phase)")
        }
        XCTAssertEqual(context.seatID, .seat5)
        XCTAssertEqual(process.forceQuitCalls, 0)
        XCTAssertEqual(store.restoreCalls, 0)
        XCTAssertTrue(try journal.hasPending())
        XCTAssertTrue(phase.allowsForceQuit)
        XCTAssertEqual(phase.forceQuitPrompt, .restorePreviousAccountAfterFailedSwitch)

        await engine.acknowledge()
        let afterDecline = await engine.currentPhase()
        guard case .failed(.recoveryQuitTimedOut) = afterDecline else {
            return XCTFail("decline must keep recoveryQuitTimedOut, got \(afterDecline)")
        }
        XCTAssertEqual(store.restoreCalls, 0)
        XCTAssertTrue(try journal.hasPending())
        XCTAssertNotEqual(afterDecline, .ready(.seat5))

        // Force quit confirmation path: wait after force quit succeeds.
        process.waitResults = [true]
        process.waits = 0
        process.pids = [77]
        let restored = await engine.forceQuitAfterTimeout()
        guard case .failed(.verificationFailed(let seatID)) = restored else {
            return XCTFail("expected verificationFailed after confirmed force quit, got \(restored)")
        }
        XCTAssertEqual(seatID, .seat5)
        XCTAssertEqual(process.forceQuitCalls, 1)
        XCTAssertEqual(store.restoreCalls, 1)
        XCTAssertFalse(try journal.hasPending())
    }

    func testLaunchExitsImmediatelyWithMatchingSubjectNeverReady() async throws {
        let process = FakeCursorProcess()
        process.waitResults = [true, true]
        process.clearPIDsOnLaunch = true
        let store = FakeSessionStore()
        let plan = try makePlan(subject: "auth0|crash")
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorBarLaunchExit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let profile = SharedCursorProfile.default(homeDirectory: home)

        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { store },
            recoveryJournal: MemoryAccountSwitchRecoveryJournal(),
            sharedProfile: profile,
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(50),
            verifyTimeout: .milliseconds(80),
            recoveryExitWaitTimeout: .milliseconds(50)
        )
        _ = await engine.beginRequest(seatID: .seat2)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat2))
        XCTAssertNotEqual(phase, .ready(.seat2))
        guard case .failed(.verificationFailed) = phase else {
            return XCTFail("expected verificationFailed rollback, got \(phase)")
        }
        XCTAssertEqual(store.injectCalls, 1)
        XCTAssertEqual(store.restoreCalls, 1)
        XCTAssertEqual(process.forceQuitCalls, 0)
    }

    func testStaleCodeLockWithoutPIDNeverReady() async throws {
        let process = FakeCursorProcess()
        process.waitResults = [true, true]
        process.clearPIDsOnLaunch = true
        let store = FakeSessionStore()
        let plan = try makePlan(subject: "auth0|lock")
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorBarStaleLock-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let profile = SharedCursorProfile.default(homeDirectory: home)
        process.codeLockDirectories = [profile.rootDirectory.path]

        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { store },
            recoveryJournal: MemoryAccountSwitchRecoveryJournal(),
            sharedProfile: profile,
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(50),
            verifyTimeout: .milliseconds(80),
            recoveryExitWaitTimeout: .milliseconds(50)
        )
        _ = await engine.beginRequest(seatID: .seat3)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat3))
        XCTAssertNotEqual(phase, .ready(.seat3))
        guard case .failed(.verificationFailed) = phase else {
            return XCTFail("expected verificationFailed, got \(phase)")
        }
        XCTAssertEqual(process.forceQuitCalls, 0)
    }

    func testStaleAttemptCannotCompleteNewerSwitch() async throws {
        let contextOld = SwitchContext(seatID: .seat1, generation: 1)
        let contextNew = SwitchContext(seatID: .seat2, generation: 2)
        let verifying = IDESwitchPhase.verifying(
            contextNew,
            VerificationEvidence(processReady: true, identityVerified: false)
        )
        let ignored = IDESwitchReducer.reduce(phase: verifying, event: .identityVerified(contextOld.generation))
        XCTAssertEqual(try! XCTUnwrap(success(ignored)), verifying)

        let completed = IDESwitchReducer.reduce(phase: verifying, event: .identityVerified(contextNew.generation))
        XCTAssertEqual(try! XCTUnwrap(success(completed)), .ready(.seat2))
    }

    func testRollbackFailureIsTerminal() async throws {
        let process = FakeCursorProcess()
        process.exitAfterWaits = 1
        process.launchError = NSError(domain: "test", code: 2)
        let store = FakeSessionStore()
        store.restoreError = .restoreFailed
        let plan = try makePlan(subject: "auth0|rollback")
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { store },
            recoveryJournal: MemoryAccountSwitchRecoveryJournal(),
            sharedProfile: SharedCursorProfile.default(homeDirectory: home),
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(50)
        )
        _ = await engine.beginRequest(seatID: .seat5)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat5))
        guard case .failed(.rollbackFailed(let seatID)) = phase else {
            return XCTFail("expected rollbackFailed, got \(phase)")
        }
        XCTAssertEqual(seatID, .seat5)
        XCTAssertFalse(phase.allowsForceQuit)
        XCTAssertNotEqual(phase, .ready(.seat5))
    }

    func testJournalSurvivesFreshEngineAndRestoresOnStartupWhenCursorStopped() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let store = FakeSessionStore()
        let secretBlob = Data("prior-access-secret".utf8)
        let backup = AuthRowBackup(rows: [.accessToken: .present(secretBlob)])
        store.backup = backup
        let plan = try makePlan(subject: "auth0|crash")
        // Crash window: journal durable + inject committed, process/app gone before verify.
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat2, generation: 3, backup: backup)
        )
        _ = try store.inject(plan: plan)
        XCTAssertTrue(try journal.hasPending())

        let processB = FakeCursorProcess()
        processB.pids = []
        let storeB = FakeSessionStore()
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let profile = SharedCursorProfile.default(homeDirectory: home)
        let engineB = IDESwitchEngine(
            process: processB,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { storeB },
            recoveryJournal: journal,
            sharedProfile: profile,
            homeDirectory: home
        )
        let phase = await engineB.bootstrapPendingRecovery()
        XCTAssertEqual(phase, .idle)
        XCTAssertEqual(storeB.restoreCalls, 1)
        XCTAssertEqual(processB.forceQuitCalls, 0)
        XCTAssertFalse(try journal.hasPending())
        let accepted = await engineB.beginRequest(seatID: .seat3)
        guard case .success(.confirming(.seat3)) = accepted else {
            return XCTFail("expected confirming after recovery resolved, got \(accepted)")
        }
    }

    func testJournalBeforeInjectCrashThenStartupRestore() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let backup = AuthRowBackup(rows: [
            .accessToken: .present(Data("prior-access-secret".utf8)),
            .refreshToken: .present(Data("prior-refresh-secret".utf8)),
        ])
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat1, generation: 9, backup: backup)
        )
        let process = FakeCursorProcess()
        process.pids = []
        let store = FakeSessionStore()
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
        XCTAssertEqual(phase, .idle)
        XCTAssertEqual(store.restoreCalls, 1)
        XCTAssertEqual(process.forceQuitCalls, 0)
        XCTAssertFalse(try journal.hasPending())
    }

    func testStartupRecoveryWithRunningCursorNeverAutoForceQuits() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let backup = AuthRowBackup(rows: [.accessToken: .present(Data("prior-access-secret".utf8))])
        try journal.save(
            PendingAccountSwitchRecovery(seatID: .seat3, generation: 4, backup: backup)
        )
        let process = FakeCursorProcess()
        process.pids = [55]
        process.waitResults = [false]
        let store = FakeSessionStore()
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .failure(.refreshFailed)),
            sessionStoreFactory: { store },
            recoveryJournal: journal,
            sharedProfile: SharedCursorProfile.default(homeDirectory: home),
            homeDirectory: home,
            recoveryExitWaitTimeout: .milliseconds(20)
        )
        let phase = await engine.bootstrapPendingRecovery()
        guard case .pendingStartupRecovery(let context) = phase else {
            return XCTFail("expected pendingStartupRecovery, got \(phase)")
        }
        XCTAssertEqual(context.seatID, .seat3)
        XCTAssertEqual(process.forceQuitCalls, 0)
        XCTAssertEqual(process.quitCalls, 0)
        XCTAssertEqual(store.restoreCalls, 0)
        XCTAssertTrue(try journal.hasPending())
        let blocked = await engine.beginRequest(seatID: .seat1)
        guard case .failure(.pendingRecoveryOutstanding) = blocked else {
            return XCTFail("expected pendingRecoveryOutstanding, got \(blocked)")
        }
    }

    func testCorruptJournalBlocksSwitchWithoutSecrets() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let secret = "super-secret-refresh-token-value"
        try journal.save(
            PendingAccountSwitchRecovery(
                seatID: .seat2,
                generation: 1,
                backup: AuthRowBackup(rows: [.refreshToken: .present(Data(secret.utf8))])
            )
        )
        journal.markCorruptOnLoad()
        let process = FakeCursorProcess()
        process.pids = []
        let store = FakeSessionStore()
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
        guard case .failed(.pendingRecoveryCorrupt) = phase else {
            return XCTFail("expected pendingRecoveryCorrupt, got \(phase)")
        }
        XCTAssertFalse(phase.menuStatusText?.contains(secret) == true)
        XCTAssertEqual(process.forceQuitCalls, 0)
        let blocked = await engine.beginRequest(seatID: .seat4)
        guard case .failure(.pendingRecoveryOutstanding) = blocked else {
            return XCTFail("expected pendingRecoveryOutstanding")
        }
    }

    func testJournalDescriptionRedactsSecretsAndStaticForbidsPlaintextRecoveryFiles() throws {
        let secret = "eyJhbGciOiJub25lIn0.payload.sig-secret"
        let recovery = PendingAccountSwitchRecovery(
            seatID: .seat1,
            generation: 2,
            backup: AuthRowBackup(rows: [.accessToken: .present(Data(secret.utf8))])
        )
        XCTAssertFalse(recovery.description.contains(secret))
        XCTAssertFalse(String(describing: recovery.backup).contains(secret))
        XCTAssertTrue(recovery.description.contains("present") || recovery.description.contains("rows="))

        let journalSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Adapters/AccountSwitchRecoveryJournal.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(journalSource.contains("KeychainAccountSwitchRecoveryJournal"))
        XCTAssertFalse(journalSource.contains("writeToFile"))
        XCTAssertFalse(journalSource.contains("FileManager.default.createFile"))
        XCTAssertTrue(journalSource.contains("app.cursorbar") || journalSource.contains("ownedServiceName"))
    }

    func testDetectorMatchesSubjectAndReturnsNilOnAmbiguity() throws {
        let access = try XCTUnwrap(AccessToken("access"))
        let refresh = try XCTUnwrap(RefreshToken("refresh"))
        let seat1 = StoredSeatRecord(
            seatID: .seat1,
            identity: .subject("auth0|one"),
            access: access,
            refresh: refresh,
            email: Email("one@example.com"),
            expiresAt: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )
        let seat2 = StoredSeatRecord(
            seatID: .seat2,
            identity: .subject("auth0|two"),
            access: access,
            refresh: refresh,
            email: Email("two@example.com"),
            expiresAt: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )
        let seat3 = StoredSeatRecord(
            seatID: .seat3,
            identity: .email(try XCTUnwrap(Email("fallback@example.com"))),
            access: access,
            refresh: refresh,
            email: Email("fallback@example.com"),
            expiresAt: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )
        let detector = ActiveIDESeatDetector(
            identityReader: { CursorIDEIdentity(subject: "auth0|two", email: Email("ignored@example.com")) },
            rosterLoader: { [seat1, seat2, seat3] }
        )
        XCTAssertEqual(detector.detect(), .seat2)

        let emailDetector = ActiveIDESeatDetector(
            identityReader: { CursorIDEIdentity(subject: "unknown", email: Email("Fallback@example.com")) },
            rosterLoader: { [seat1, seat2, seat3] }
        )
        XCTAssertEqual(emailDetector.detect(), .seat3)

        let ambiguous = StoredSeatRecord(
            seatID: .seat4,
            identity: .subject("auth0|one"),
            access: access,
            refresh: refresh,
            email: Email("dup@example.com"),
            expiresAt: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )
        let ambiguousDetector = ActiveIDESeatDetector(
            identityReader: { CursorIDEIdentity(subject: "auth0|one", email: nil) },
            rosterLoader: { [seat1, ambiguous] }
        )
        XCTAssertNil(ambiguousDetector.detect())

        let unknown = ActiveIDESeatDetector(
            identityReader: { CursorIDEIdentity(subject: "auth0|none", email: nil) },
            rosterLoader: { [seat1, seat2, seat3] }
        )
        XCTAssertNil(unknown.detect())
    }

    func testConcurrentBeginRejected() async {
        let context = SwitchContext(seatID: .seat1, generation: 1)
        let inFlight = IDESwitchReducer.reduce(
            phase: .updatingSession(context),
            event: .requestOpen(.seat2)
        )
        guard case .failure(.switchInProgress) = inFlight else {
            return XCTFail("expected in-flight reject")
        }
    }

    func testNoRestartSurfaceOnFocusAuthRefreshPaths() {
        let confirmed = ConfirmedIDEOpen.confirmed(seatID: .seat1)
        XCTAssertEqual(confirmed.seatID, .seat1)
        XCTAssertFalse(String(describing: confirmed).localizedCaseInsensitiveContains("token"))
    }

    func testRollbackFailureRetainsJournal() async throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        let process = FakeCursorProcess()
        process.exitAfterWaits = 1
        process.launchError = NSError(domain: "test", code: 1)
        let store = FakeSessionStore()
        store.restoreError = .restoreFailed
        let plan = try makePlan(subject: "auth0|rollback-retain")
        let home = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let engine = IDESwitchEngine(
            process: process,
            preparer: FixedAccountSwitchSessionPreparer(result: .success(plan)),
            sessionStoreFactory: { store },
            recoveryJournal: journal,
            sharedProfile: SharedCursorProfile.default(homeDirectory: home),
            homeDirectory: home,
            exitWaitTimeout: .milliseconds(50)
        )
        _ = await engine.beginRequest(seatID: .seat5)
        let phase = await engine.runConfirmed(.confirmed(seatID: .seat5))
        guard case .failed(.rollbackFailed) = phase else {
            return XCTFail("expected rollbackFailed, got \(phase)")
        }
        XCTAssertTrue(try journal.hasPending())
        let blocked = await engine.beginRequest(seatID: .seat1)
        guard case .failure(.pendingRecoveryOutstanding) = blocked else {
            return XCTFail("expected pendingRecoveryOutstanding, got \(blocked)")
        }
    }

    func testCorruptJournalHasPendingWithoutDecoding() throws {
        let journal = MemoryAccountSwitchRecoveryJournal()
        try journal.save(
            PendingAccountSwitchRecovery(
                seatID: .seat2,
                generation: 1,
                backup: AuthRowBackup(rows: [.accessToken: .present(Data("x".utf8))])
            )
        )
        journal.markCorruptOnLoad()
        XCTAssertTrue(try journal.hasPending())
        XCTAssertThrowsError(try journal.load()) { error in
            XCTAssertEqual(error as? AccountSwitchRecoveryJournalError, .corrupt)
        }
    }

    private func success(_ result: Result<IDESwitchPhase, IDESwitchRejectReason>) -> IDESwitchPhase? {
        switch result {
        case .success(let phase):
            return phase
        case .failure:
            return nil
        }
    }

    private func makePlan(subject: String) throws -> CursorAuthSessionPlan {
        let accessJWT = unsignedJWT(sub: subject, exp: 1_900_000_000)
        let access = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: accessJWT))
        let refresh = try XCTUnwrap(RefreshToken(unsignedJWT(sub: subject, exp: 1_900_000_000)))
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
