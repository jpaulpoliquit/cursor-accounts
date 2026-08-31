import Foundation

/// Complete Ultra spending read model for one seat. Credential-free and Codable-safe.
public struct SeatUsageSnapshot: Codable, Sendable, Equatable, Hashable {
    public let seatID: SeatID
    public let plan: PlanInfo
    public let period: PeriodUsageDetail
    public let hardLimit: HardLimit
    public let credits: CreditBalance
    public let policy: UsagePolicy
    public let fetchedAt: Date

    public init(
        seatID: SeatID,
        plan: PlanInfo,
        period: PeriodUsageDetail,
        hardLimit: HardLimit,
        credits: CreditBalance,
        policy: UsagePolicy,
        fetchedAt: Date
    ) {
        self.seatID = seatID
        self.plan = plan
        self.period = period
        self.hardLimit = hardLimit
        self.credits = credits
        self.policy = policy
        self.fetchedAt = fetchedAt
    }

    public var onDemand: OnDemandState {
        OnDemandState(
            mode: hardLimit.onDemandMode,
            individualUsed: period.spendLimitUsage?.individualUsed,
            individualLimit: period.spendLimitUsage?.individualLimit
        )
    }

    public var statusPill: SeatStatusPill? {
        let included = SeatStatusPill.includedPool(
            usage: period.usage,
            displayMessage: period.displayMessage
        )
        let spend: SeatStatusPill.Input.OnDemandSpend =
            onDemand.isConsuming ? .consuming : .idle
        return SeatStatusPill.derive(
            .init(included: included, mode: onDemand.mode, spend: spend)
        )
    }
}

/// Per-seat refresh outcome. Failures keep prior last-known snapshots elsewhere.
public enum SeatUsageRefreshOutcome: Sendable, Equatable {
    case refreshed(SeatUsageSnapshot)
    case failed(message: String)
    case skippedSignedOut
}

public struct UsageRefreshReport: Sendable, Equatable {
    public let outcomes: [SeatID: SeatUsageRefreshOutcome]
    /// Binding epochs captured when refresh started; apply must verify still current.
    public let bindingEpochs: [SeatID: UInt64]

    public init(
        outcomes: [SeatID: SeatUsageRefreshOutcome],
        bindingEpochs: [SeatID: UInt64] = [:]
    ) {
        self.outcomes = outcomes
        self.bindingEpochs = bindingEpochs
    }
}

public enum UsageRefreshScope: Sendable, Equatable, Hashable {
    case all
    case seat(SeatID)
}

/// Typed refresh lifecycle for AppModel. Not a boolean isRefreshing flag.
public enum UsageRefreshPhase: Sendable, Equatable {
    case idle
    case refreshing(UsageRefreshScope)
    case settled(UsageRefreshReport)
}

/// Refresher commit result. Stale generations never surface an applied report.
public enum UsageRefreshCommit: Sendable, Equatable {
    case applied(UsageRefreshReport)
    case discarded
}

/// Typed SetHardLimit lifecycle. Write-ok/read-fail is not plain failure.
public enum SetHardLimitPhase: Sendable, Equatable {
    case idle
    case confirming(SeatID)
    case writing(SeatID)
    case succeeded(SeatUsageSnapshot)
    /// Write succeeded; re-read failed. Prior displayed data is stale/uncertain.
    case writtenUnconfirmed(SeatID)
    case failed(SeatID, message: String)
}

/// SetHardLimit outcome after policy + write. Distinct from pre-write failures.
public enum SetHardLimitSuccess: Sendable, Equatable {
    case applied(SeatUsageSnapshot)
    case writtenUnconfirmed(SeatID)
}
