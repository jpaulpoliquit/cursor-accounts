import CursorBarAdapters
import CursorBarDomain
import Foundation

extension AppModel {
    /// Debounced usage refresh when the menu bar menu opens. Joins in-flight card refresh.
    func refreshOnMenuOpen() {
        openRefreshScheduler.schedule(.menuBar) { [weak self] surfaces in
            self?.performOpenRefresh(for: surfaces)
        }
    }

    /// Debounced refresh when Dashboard appears or becomes key. Refreshes cards + current chart scope.
    func refreshOnDashboardOpen() {
        dashboardVisible = true
        openRefreshScheduler.schedule(.dashboard) { [weak self] surfaces in
            self?.performOpenRefresh(for: surfaces)
        }
    }

    /// Dashboard closed or disappeared. Stops history warm and drops raw event months.
    func noteDashboardClosed() {
        guard dashboardVisible else { return }
        dashboardVisible = false
        usageSeries.pauseBackgroundWork()
    }

    func refreshCardsIfPolicyAllows(trigger: UsageFetchTrigger) {
        let surface: UsageSurface = dashboardVisible ? .dashboard : .hidden
        let fetchedAt = usageBySeat.values.map(\.fetchedAt).max()
        switch UsageWorkPolicy.decision(
            surface: surface,
            work: .cardRefresh,
            trigger: trigger,
            hasLastKnown: !usageBySeat.isEmpty,
            fetchedAt: fetchedAt
        ) {
        case .showThenFetch, .fetchNow:
            usageRefresh.refreshAllIfIdle(trigger: trigger)
        case .skip, .cancel, .opportunistic:
            break
        }
    }

    func performOpenRefresh(for surfaces: Set<OpenRefreshSurface>) {
        guard !presentation.ideSwitchPhase.blocksOtherOpenActions else { return }
        if surfaces.contains(.dashboard) {
            dashboardVisible = true
        }
        let surface = UsageWorkPolicy.surface(from: surfaces)
        let now = Date()
        let cardFetchedAt = usageBySeat.values.map(\.fetchedAt).max()
        switch UsageWorkPolicy.decision(
            surface: surface,
            work: .cardRefresh,
            trigger: .surfaceOpen,
            hasLastKnown: !usageBySeat.isEmpty,
            fetchedAt: cardFetchedAt,
            now: now
        ) {
        case .showThenFetch, .fetchNow:
            usageRefresh.refreshAllIfIdle()
        case .skip, .cancel, .opportunistic:
            break
        }
        switch UsageWorkPolicy.decision(
            surface: surface,
            work: .seriesRefresh,
            trigger: .surfaceOpen,
            hasLastKnown: usageSeries.series != nil,
            fetchedAt: usageSeries.lastSettledAt,
            now: now
        ) {
        case .showThenFetch, .fetchNow:
            usageSeries.refreshIfIdle()
        case .skip, .cancel, .opportunistic:
            break
        }
        switch UsageWorkPolicy.decision(
            surface: surface,
            work: .historyWarm,
            trigger: .surfaceOpen,
            hasLastKnown: true,
            fetchedAt: now,
            now: now
        ) {
        case .opportunistic:
            usageSeries.warmConnectedSeatsIfNeeded()
        case .cancel:
            usageSeries.pauseBackgroundWork()
        case .skip, .showThenFetch, .fetchNow:
            break
        }
    }
}
