import CursorBarAdapters
import CursorBarDomain
import Foundation
import Observation

/// Owns chart scope/metric/range, series refresh, and Aggregate token summary outside AppModel projection.
@MainActor
@Observable
final class UsageSeriesCoordinator {
    var phase: UsageSeriesRefreshPhase = .idle
    var series: UsageSeries?
    var tokenSummary: UsageTokenSummary?
    var insights: ActivityInsights?
    var insightsPhase: UsageSeriesRefreshPhase = .idle
    var historyWarmPhase: HistoryWarmPhase = .idle
    var scope: UsageScope = .allAccounts
    var metric: UsageMetric = .tokens
    var range: UsageRange = .defaultMonth()
    var allTimeBounds: AllTimeHistoryBounds?
    var lastChunkCount: Int = 0
    var lastMaxInFlight: Int = 0

    @ObservationIgnored let refresher: UsageSeriesRefresher
    @ObservationIgnored let tokenSummaryRefresher: UsageTokenSummaryRefresher
    @ObservationIgnored let insightsRefresher: UsageInsightsRefresher
    @ObservationIgnored var loadCredentials: () -> [UsageSeriesRefresher.SeatCredential] = { [] }
    @ObservationIgnored private var connectedScopes: () -> [(UsageScope, String)] = { [(.allAccounts, "All Accounts")] }
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored var generation: UInt64 = 0
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var warmTasks: [SeatID: Task<Void, Never>] = [:]
    @ObservationIgnored var warmGenerations: [SeatID: UInt64] = [:]
    @ObservationIgnored var historyWarmPhasesBySeat: [SeatID: HistoryWarmPhase] = [:]
    @ObservationIgnored var timeZone: TimeZone = .current
    @ObservationIgnored var resolveAllTimeBounds: () async -> AllTimeHistoryBounds? = { nil }
    @ObservationIgnored var lastSettledAt: Date?
    @ObservationIgnored var lastSettledScope: UsageScope?
    @ObservationIgnored var lastSettledRange: UsageRange?
    @ObservationIgnored let chartSnapshotStore: UsageChartSnapshotStore?

    init(
        refresher: UsageSeriesRefresher = UsageSeriesRefresher(),
        tokenSummaryRefresher: UsageTokenSummaryRefresher = UsageTokenSummaryRefresher(),
        insightsRefresher: UsageInsightsRefresher = UsageInsightsRefresher(),
        timeZone: TimeZone = .current,
        chartSnapshotStore: UsageChartSnapshotStore? = nil
    ) {
        self.refresher = refresher
        self.tokenSummaryRefresher = tokenSummaryRefresher
        self.insightsRefresher = insightsRefresher
        self.timeZone = timeZone
        self.range = .defaultMonth(timeZone: timeZone)
        self.chartSnapshotStore = chartSnapshotStore
        if let snapshot = chartSnapshotStore?.load() {
            applyHydratedChart(snapshot)
        }
    }

    func configure(
        loadCredentials: @escaping () -> [UsageSeriesRefresher.SeatCredential],
        connectedScopes: @escaping () -> [(UsageScope, String)],
        onChange: @escaping () -> Void,
        resolveAllTimeBounds: (() async -> AllTimeHistoryBounds?)? = nil
    ) {
        self.loadCredentials = loadCredentials
        self.connectedScopes = connectedScopes
        self.onChange = onChange
        if let resolveAllTimeBounds {
            self.resolveAllTimeBounds = resolveAllTimeBounds
        }
    }

    /// Compatibility for presentation dump / older call sites.
    var allTimeBound: (start: UsageDayKey, end: UsageDayKey)? {
        guard let bounds = allTimeBounds,
              let window = bounds.chartWindow(for: scope)
        else { return nil }
        return window
    }

    var scopeOptions: [(UsageScope, String)] {
        connectedScopes()
    }

    var costAvailable: Bool {
        series?.costAvailable == true
    }

    var resolvedMetric: UsageMetric {
        if metric == .costCents, !costAvailable {
            return .tokens
        }
        return metric
    }

    var canGoPrevious: Bool { range.canGoPrevious }
    var canGoNext: Bool { range.canGoNext }
    var showsTodayAction: Bool {
        if case .month(let month) = range {
            return month != YearMonth.current(timeZone: timeZone)
        }
        return false
    }

    var rangeTitle: String {
        range.title(timeZone: timeZone)
    }

    var coverageStatusCaption: String? {
        if let temporal = tokenSummary?.temporalCoverage?.caption {
            return temporal
        }
        if let month = series?.monthCoverageCaption {
            return month
        }
        if let bound = allTimeBounds?.boundCoverageCaption, case .allTime = range {
            return bound
        }
        return tokenSummary?.coverage.caption ?? series?.coverage.caption
    }

    var accessibilityDescriptor: String {
        guard let series else {
            return "Usage chart, no data"
        }
        let scopeLabel = scopeOptions.first(where: { $0.0 == scope })?.1
            ?? UsageScopeLabels.label(for: scope, accountLabel: nil)
        var base = UsageChartAccessibility.descriptor(
            metric: resolvedMetric,
            scopeLabel: scopeLabel,
            rangeStart: series.rangeStart,
            rangeEnd: series.rangeEnd,
            coverage: series.coverage,
            pointCount: series.points.count
        )
        base += ", \(range.accessibilityLabel)"
        if let hint = range.utcEdgeOverlapHint {
            base += ", \(hint)"
        }
        if let caption = coverageStatusCaption {
            base += ", \(caption)"
        }
        if case .allTime = range {
            base += ", account age bound, not proven entire history"
        }
        return base
    }

    func selectScope(_ next: UsageScope) {
        guard scope != next else { return }
        scope = next
        if case .allTime = range {
            if let window = allTimeBounds?.refreshingEnd(
                to: UsageDayKey.utcDay(containing: Date())
            ).chartWindow(for: next) {
                range = interactiveAllTimeRange(window: window)
            }
        }
        refresh()
    }

    func selectMetric(_ next: UsageMetric) {
        if next == .costCents, !costAvailable { return }
        metric = next
        onChange()
    }

    func selectRange(_ next: UsageRange) {
        guard range != next else { return }
        range = next
        refresh()
    }

    func goToPreviousMonth() {
        guard let previous = range.previous() else { return }
        selectRange(previous)
    }

    func goToNextMonth() {
        guard let next = range.next(timeZone: timeZone) else { return }
        selectRange(next)
    }

    func goToCurrentMonth() {
        selectRange(.defaultMonth(timeZone: timeZone))
    }

    func selectAllTime() {
        Task { [weak self] in
            guard let self else { return }
            await self.ensureAllTimeBoundsCurrent()
            guard let window = self.allTimeBounds?.chartWindow(for: self.scope) else { return }
            self.selectRange(self.interactiveAllTimeRange(window: window))
        }
    }

    var isRefreshing: Bool {
        phase == .refreshing || insightsPhase == .refreshing
    }

    /// Open-refresh joins in-flight work and skips a fresh settled scope/range.
    func refreshIfIdle() {
        guard !isRefreshing else { return }
        if lastSettledScope == scope,
           lastSettledRange == range,
           !UsageCachePolicy.needsNetworkFetch(
               trigger: .surfaceOpen,
               fetchedAt: lastSettledAt
           )
        {
            return
        }
        refresh()
    }

    /// Stale-generation guard used by tests: advancing generation drops in-flight apply.
    func bumpGenerationForTests() {
        generation &+= 1
        Task { await insightsRefresher.bumpGenerationForTests() }
    }

    var insightsAccessibilityDescriptor: String {
        insights?.accessibilityDescriptor ?? "Work insights, no data"
    }

    var heatmapTimeZone: TimeZone {
        if let identifier = insights?.timeZoneIdentifier, let zone = TimeZone(identifier: identifier) {
            return zone
        }
        return timeZone
    }

    /// Privacy-safe seat labels for All Accounts Insights hover contributions.
    var insightsAccountLabels: [SeatID: String] {
        var labels: [SeatID: String] = [:]
        for (scope, title) in connectedScopes() {
            if case .account(let seatID) = scope {
                labels[seatID] = title
            }
        }
        return labels
    }

    func applyAllTimeBoundsForTests(_ bounds: AllTimeHistoryBounds?) {
        allTimeBounds = bounds
    }
}
