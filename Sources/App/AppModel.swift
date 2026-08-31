import CursorBarAdapters
import CursorBarDomain
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    /// Verify-only handle for AppKit dashboard hosting (`--open-dashboard`).
    static var sharedForVerify: AppModel?

    var presentation: AppPresentation
    var identityPolicy: IdentityDisplayPolicy {
        didSet {
            policyStore.save(identityPolicy)
            reproject()
        }
    }

    @ObservationIgnored var aggregate: AggregateSnapshot
    @ObservationIgnored var bootstrapPhase: BootstrapPhase = .pending
    @ObservationIgnored var usageBySeat: [SeatID: SeatUsageSnapshot] = [:]
    @ObservationIgnored var bindingEpochs = SeatBindingEpochRegistry()
    @ObservationIgnored var bootstrapRecoveryTask: Task<Void, Never>?
    @ObservationIgnored var setHardLimitPhase: SetHardLimitPhase = .idle
    @ObservationIgnored var focusedSeatID: SeatID

    @ObservationIgnored let session: BootstrapSession
    @ObservationIgnored let keychain: any SeatCredentialStore
    @ObservationIgnored let refresher: SeatUsageRefresher
    @ObservationIgnored let policyStore: IdentityDisplayPolicyStore
    @ObservationIgnored let focusStore: FocusedSeatStore
    @ObservationIgnored let ideSwitch: IDESwitchCoordinator
    @ObservationIgnored let usageRefresh: UsageRefreshCoordinator
    @ObservationIgnored let confirmation: ConfirmationCommandCoordinator
    @ObservationIgnored let seatAuth: SeatAuthCommandCoordinator
    let usageSeries: UsageSeriesCoordinator
    @ObservationIgnored let openRefreshScheduler = OpenRefreshScheduler()
    @ObservationIgnored let cardSnapshotStore: UsageCardSnapshotStore
    @ObservationIgnored var dashboardVisible = false
    var dashboardTab: DashboardTab = .accounts
    var accountLayout: DashboardAccountLayout = .table
    var accountSort: DashboardAccountSort = .reset
    var accountSortDirection: DashboardSortDirection = DashboardAccountSort.reset.defaultDirection
    var selectedAccountID: SeatID?
    var modelSort: DashboardModelSort = .tokens
    var modelSortDirection: DashboardSortDirection = DashboardModelSort.tokens.defaultDirection
    #if DEBUG
    var dashboardLayoutPrototype: DashboardLayoutPrototype = .profileColumn
    #endif
    @ObservationIgnored var signedInCredentials: [SeatUsageRefresher.SeatCredential] = []
    @ObservationIgnored var signedInCredentialsValid = false

    init(
        orchestrator: BootstrapOrchestrator = BootstrapOrchestrator(),
        keychain: any SeatCredentialStore = SeatKeychainStore(),
        refresher: SeatUsageRefresher? = nil,
        seriesRefresher: UsageSeriesRefresher? = nil,
        authEngine: AuthEngine? = nil,
        policyStore: IdentityDisplayPolicyStore = IdentityDisplayPolicyStore(),
        focusStore: FocusedSeatStore = FocusedSeatStore(),
        ideSwitchEngine: IDESwitchEngine? = nil,
        ideSwitchDetector: ActiveIDESeatDetector? = nil,
        confirmationGate: ConfirmationGate? = nil,
        cardSnapshotStore: UsageCardSnapshotStore = UsageCardSnapshotStore(),
        chartSnapshotStore: UsageChartSnapshotStore = UsageChartSnapshotStore(),
        autostart: Bool = true
    ) {
        // Never SecItemCopyMatching on the main-thread init path; Keychain can block on ACL UI.
        let shell = AggregateSnapshot.empty
        self.aggregate = shell
        let usageGate = FetchConcurrencyGate(
            limit: FetchConcurrencyGate.defaultPerSeatLimit,
            isolation: .perSeat
        )
        let resolvedRefresher = refresher ?? SeatUsageRefresher(gate: usageGate)
        let resolvedSeries = seriesRefresher ?? UsageSeriesRefresher(gate: usageGate)
        self.keychain = keychain
        self.refresher = resolvedRefresher
        self.policyStore = policyStore
        self.focusStore = focusStore
        self.cardSnapshotStore = cardSnapshotStore
        self.usageBySeat = cardSnapshotStore.load()
        self.identityPolicy = policyStore.load()
        self.focusedSeatID = focusStore.load()
        let resolvedAuth = authEngine ?? AuthEngine(
            store: keychain,
            browser: WorkspaceBrowserPresenter()
        )
        let session = BootstrapSession(shell: shell) {
            try await orchestrator.run()
        }
        self.session = session
        let resolvedEngine = ideSwitchEngine ?? IDESwitchEngine(
            auth: resolvedAuth,
            credentialStore: keychain,
            tracer: FileAccountSwitchTrace.live()
        )
        let resolvedDetector = ideSwitchDetector ?? ActiveIDESeatDetector(credentialStore: keychain)
        let ideSwitch = IDESwitchCoordinator(engine: resolvedEngine, detector: resolvedDetector)
        self.ideSwitch = ideSwitch
        self.usageRefresh = UsageRefreshCoordinator(refresher: resolvedRefresher)
        self.usageSeries = UsageSeriesCoordinator(
            refresher: resolvedSeries,
            tokenSummaryRefresher: UsageTokenSummaryRefresher(gate: usageGate),
            insightsRefresher: UsageInsightsRefresher(gate: usageGate),
            chartSnapshotStore: chartSnapshotStore
        )
        self.seatAuth = SeatAuthCommandCoordinator(authEngine: resolvedAuth)
        self.confirmation = ConfirmationCommandCoordinator(
            gate: confirmationGate ?? SystemConfirmationGate()
        )
        self.presentation = SeatPresentationProjector.project(
            aggregate: shell,
            usageBySeat: usageBySeat,
            identityPolicy: policyStore.load(),
            focusedSeatID: focusStore.load(),
            loginPhases: [:],
            bootstrapPhase: .pending,
            usageRefreshPhase: .idle,
            setHardLimitPhase: .idle,
            ideSwitchPhase: ideSwitch.phase,
            desktopBoundSeatID: ideSwitch.desktopBoundSeatID
        )

        usageRefresh.configure(
            loadCredentials: { [weak self] in self?.loadSignedInCredentials() ?? [] },
            applyReport: { [weak self] report in self?.applyUsageRefreshReport(report) },
            onChange: { [weak self] in self?.reproject() },
            bindingEpoch: { [weak self] seatID in self?.bindingEpochs.current(for: seatID) ?? 0 },
            fetchedAt: { [weak self] seatID in self?.usageBySeat[seatID]?.fetchedAt }
        )
        usageSeries.configure(
            loadCredentials: { [weak self] in self?.loadSignedInCredentials() ?? [] },
            connectedScopes: { [weak self] in self?.usageScopeOptions() ?? [(.allAccounts, "All Accounts")] },
            onChange: {},
            resolveAllTimeBounds: { [weak self] in
                guard let self else { return nil }
                let credentials = self.loadSignedInCredentials()
                let epochs = self.bindingEpochs.snapshot(for: credentials.map(\.seatID))
                let resolved = await AllTimeBoundLookup.resolve(
                    credentials: credentials,
                    bindingEpochs: epochs
                )
                guard epochs.allSatisfy({ self.bindingEpochs.isCurrent(seatID: $0.key, epoch: $0.value) }) else {
                    return nil
                }
                return resolved
            }
        )
        seatAuth.configure(
            identityPolicy: { [weak self] in self?.identityPolicy ?? .maskEmail },
            mutateAggregate: { [weak self] mutate in
                guard let self else { return }
                self.invalidateSignedInCredentials()
                mutate(&self.aggregate)
            },
            removeAccountCaches: { [weak self] seatID in await self?.removeAccountCaches(seatID: seatID) },
            warmHistory: { [weak self] seatID in
                guard let self, self.dashboardVisible else { return }
                self.usageSeries.warmHistory(for: seatID)
            },
            reloadShell: { [weak self] in self?.reloadShellFromKeychain() },
            refreshSeat: { [weak self] seatID in self?.refresh(seatID: seatID) },
            refreshSeriesAfterPurge: { [weak self] in
                self?.usageSeries.refreshAfterAccountPurgeIfNeeded()
            },
            onChange: { [weak self] in self?.reproject() }
        )
        confirmation.configure(
            currentOnDemandMode: { [weak self] seatID in
                self?.presentation.seats.first(where: { $0.seatID == seatID })?.onDemand?.mode
            },
            policyForSeat: { [weak self] seatID in
                self?.presentation.seats.first(where: { $0.seatID == seatID })?.policy
            },
            accountLabel: { [weak self] seatID in
                self?.presentation.seats.first(where: { $0.seatID == seatID })?.label.text
                    ?? "this account"
            },
            performSignOut: { [weak self] seatID in
                await self?.seatAuth.performSignOut(seatID: seatID)
            },
            performSetOnDemand: { [weak self] seatID, mode in
                await self?.performSetOnDemand(seatID: seatID, mode: mode)
            }
        )

        ideSwitch.setPhaseObserver { [weak self] in
            self?.reproject()
        }
        session.onUpdate = { [weak self] aggregate, phase, invalidatedSeatIDs in
            guard let self else { return }
            self.invalidateSignedInCredentials()
            self.aggregate = aggregate
            self.bootstrapPhase = phase
            self.ideSwitch.refreshDesktopBound()
            self.reproject()
            Task { [weak self] in
                guard let self else { return }
                for seatID in invalidatedSeatIDs {
                    await self.removeAccountCaches(seatID: seatID)
                }
                if case .settled = phase {
                    self.refreshCardsIfPolicyAllows(trigger: .bootstrap)
                }
                if !invalidatedSeatIDs.isEmpty {
                    self.reproject()
                }
            }
        }
        if autostart, !VerifyUsageCacheSeed.isRequested {
            Task { [weak self] in
                guard let self else { return }
                await self.awaitStartupRecovery()
                self.reproject()
                self.startAfterRecovery()
            }
        }
        AppModel.sharedForVerify = self
        if CommandLine.arguments.contains("--mask-email") {
            identityPolicy = .maskEmail
        }
        VerifyDashboardPresenter.applyLaunchOptions(to: self)
        if CommandLine.arguments.contains("--open-dashboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                VerifyDashboardPresenter.presentIfRequested(model: self)
            }
        }
        if !VerifyUsageCacheSeed.isRequested {
            VerifyPresentationDump.scheduleIfRequested(model: self)
        }
    }

    func startBootstrap() {
        guard !VerifyUsageCacheSeed.isRequested else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.awaitStartupRecovery()
            self.startAfterRecovery()
        }
    }
    func refreshBootstrap() { session.refresh() }
    func refreshAll() {
        usageRefresh.refreshAll()
        if dashboardVisible {
            usageSeries.refresh()
        }
    }
    func refresh(seatID: SeatID) { usageRefresh.refresh(seatID: seatID) }

    func focus(seatID: SeatID) {
        focusedSeatID = seatID
        focusStore.save(seatID)
        reproject()
    }

    func toggleMaskEmail() {
        switch identityPolicy {
        case .maskEmail: identityPolicy = .revealEmail
        case .revealEmail: identityPolicy = .maskEmail
        }
    }

    func requestSetOnDemand(seatID: SeatID, mode: OnDemandMode) {
        confirmation.requestSetOnDemand(seatID: seatID, mode: mode)
    }

    func requestSetOnDemandFixed(seatID: SeatID) {
        confirmation.requestSetOnDemandFixed(seatID: seatID)
    }

    func beginSignIn(seatID: SeatID) { seatAuth.beginSignIn(seatID: seatID) }
    func reauthenticate(seatID: SeatID) { seatAuth.reauthenticate(seatID: seatID) }
    func cancelSignIn(seatID: SeatID) { seatAuth.cancelSignIn(seatID: seatID) }
    func requestSignOutLocally(seatID: SeatID) { confirmation.requestSignOutLocally(seatID: seatID) }

    /// Single connect CTA owner. Allocates the next unused SeatID; views never select slots.
    func connectAnotherAccount() {
        switch presentation.addAccount {
        case .signingIn:
            return
        case .available(_, let seatID), .failed(_, let seatID, _):
            beginSignIn(seatID: seatID)
        }
    }

    /// Explicit menu action only. Focus/auth/refresh/on-demand never call this.
    func openCursorAsSeat(seatID: SeatID) {
        Task { await self.performOpenCursor(seatID: seatID) }
    }

    func forceQuitCursorAfterIDESwitchTimeout() {
        Task {
            guard let prompt = ideSwitch.phase.forceQuitPrompt else { return }
            guard ConfirmationPrompts.confirmForceQuitCursor(prompt: prompt) else { return }
            await ideSwitch.forceQuitAfterTimeout()
            reproject()
        }
    }

    func reloadShellFromKeychain() {
        invalidateSignedInCredentials()
        if let shell = try? BootstrapOrchestrator(keychain: keychain).shellSnapshot() {
            aggregate = shell
            pruneUsageCardsToRoster()
            reproject()
        }
    }

    private func performOpenCursor(seatID: SeatID) async {
        let accepted = await ideSwitch.beginOpen(seatID: seatID)
        reproject()
        guard accepted else { return }
        let label = presentation.seats.first(where: { $0.seatID == seatID })?.label
        guard let confirmed = ConfirmationPrompts.confirmOpenCursor(seatID: seatID, label: label) else {
            await ideSwitch.cancelOpen()
            reproject()
            return
        }
        await ideSwitch.confirmOpen(confirmed)
        reproject()
    }
}
