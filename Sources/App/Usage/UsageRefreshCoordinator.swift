import CursorBarAdapters
import CursorBarDomain
import Foundation

/// Owns one usage-refresh generation across refresh-all and per-seat refresh.
@MainActor
final class UsageRefreshCoordinator {
    private(set) var phase: UsageRefreshPhase = .idle

    private let refresher: SeatUsageRefresher
    private var loadCredentials: () -> [SeatUsageRefresher.SeatCredential] = { [] }
    private var applyReport: (UsageRefreshReport) -> Void = { _ in }
    private var onChange: () -> Void = {}
    private var bindingEpoch: (SeatID) -> UInt64 = { _ in 0 }
    private var fetchedAt: (SeatID) -> Date? = { _ in nil }

    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?

    init(refresher: SeatUsageRefresher) {
        self.refresher = refresher
    }

    func configure(
        loadCredentials: @escaping () -> [SeatUsageRefresher.SeatCredential],
        applyReport: @escaping (UsageRefreshReport) -> Void,
        onChange: @escaping () -> Void,
        bindingEpoch: @escaping (SeatID) -> UInt64 = { _ in 0 },
        fetchedAt: @escaping (SeatID) -> Date? = { _ in nil }
    ) {
        self.loadCredentials = loadCredentials
        self.applyReport = applyReport
        self.onChange = onChange
        self.bindingEpoch = bindingEpoch
        self.fetchedAt = fetchedAt
    }

    /// Cancel only a per-seat in-flight refresh. Refresh-all stays up; epoch discard drops this seat.
    func cancelForSeat(_ seatID: SeatID) {
        guard case .refreshing(.seat(let id)) = phase, id == seatID else { return }
        task?.cancel()
        generation &+= 1
        phase = .idle
        onChange()
    }

    func refreshAll() {
        begin(scope: .all) { credentials in
            let epochs = Dictionary(
                uniqueKeysWithValues: credentials.map { ($0.seatID, self.bindingEpoch($0.seatID)) }
            )
            return await self.refresher.refreshAll(credentials: credentials, bindingEpochs: epochs)
        }
    }

    var isRefreshing: Bool {
        if case .refreshing = phase { return true }
        return false
    }

    /// Open/bootstrap refresh. Joins in-flight work and skips seats whose snapshots are still fresh.
    func refreshAllIfIdle(trigger: UsageFetchTrigger = .surfaceOpen) {
        guard !isRefreshing else { return }
        let credentials = loadCredentials()
        let needed = UsageCachePolicy.credentialsNeedingFetch(
            credentials,
            seatID: { $0.seatID },
            trigger: trigger,
            fetchedAt: fetchedAt
        )
        guard !needed.isEmpty else { return }
        begin(scope: .all) { _ in
            let epochs = Dictionary(
                uniqueKeysWithValues: needed.map { ($0.seatID, self.bindingEpoch($0.seatID)) }
            )
            return await self.refresher.refreshAll(credentials: needed, bindingEpochs: epochs)
        }
    }

    func refresh(seatID: SeatID) {
        let epoch = bindingEpoch(seatID)
        begin(scope: .seat(seatID)) { credentials in
            guard let credential = credentials.first(where: { $0.seatID == seatID }) else {
                return .applied(
                    UsageRefreshReport(
                        outcomes: [seatID: .skippedSignedOut],
                        bindingEpochs: [seatID: epoch]
                    )
                )
            }
            return await self.refresher.refresh(credential: credential, bindingEpoch: epoch)
        }
    }

    private func begin(
        scope: UsageRefreshScope,
        work: @escaping ([SeatUsageRefresher.SeatCredential]) async -> UsageRefreshCommit
    ) {
        if case .refreshing(.all) = phase, case .seat = scope {
            Task { [weak self] in
                guard let self else { return }
                let commit = await work(self.loadCredentials())
                guard case .applied(let report) = commit else { return }
                self.applyReport(report)
                switch self.phase {
                case .refreshing(.all), .settled:
                    self.onChange()
                case .idle, .refreshing(.seat):
                    self.phase = .settled(report)
                    self.onChange()
                }
            }
            return
        }
        task?.cancel()
        generation &+= 1
        let token = generation
        phase = .refreshing(scope)
        onChange()
        task = Task { [weak self] in
            guard let self else { return }
            let commit = await work(self.loadCredentials())
            guard token == self.generation else { return }
            switch commit {
            case .applied(let report):
                self.applyReport(report)
                self.phase = .settled(report)
                self.onChange()
            case .discarded:
                self.phase = .idle
                self.onChange()
            }
        }
    }
}
