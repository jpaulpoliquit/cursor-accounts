import Foundation

/// Included-plan allowance in cents. Wire int64; never treat as request counts.
public struct AmountCents: Codable, Sendable, Equatable, Hashable {
    public let cents: Int64

    public init(cents: Int64) {
        self.cents = cents
    }
}

/// Dashboard `*PercentUsed` wire unit: percent points (42.5 means 42.5%), not a 0...1 fraction.
public struct PercentUsed: Codable, Sendable, Equatable, Hashable {
    public let percent: Double

    /// Rejects non-finite values. Over-100 is allowed (overage), never silently clamped.
    public init?(percent: Double) {
        guard percent.isFinite else { return nil }
        self.percent = percent
    }

    /// Trusting constructor for already-validated domain values.
    public init(unchecked percent: Double) {
        self.percent = percent
    }

    /// Unit interval derived from percent points. Prefer `percent` at the wire edge.
    public var unitFraction: Double { percent / 100.0 }

    public var isExhausted: Bool { percent >= 100 }
}

/// Opaque Dashboard accounting units. Never format as currency.
public struct OpaqueAccountingUnits: Codable, Sendable, Equatable, Hashable {
    public let raw: Int64

    public init(raw: Int64) {
        self.raw = raw
    }

    public var isPositive: Bool { raw > 0 }
}

/// Included-plan consumption for the current billing period.
public struct PeriodUsage: Codable, Sendable, Equatable, Hashable {
    public let autoPercentUsed: PercentUsed
    public let apiPercentUsed: PercentUsed
    public let totalPercentUsed: PercentUsed
    public let resetsAt: Date?

    public init(
        autoPercentUsed: PercentUsed,
        apiPercentUsed: PercentUsed,
        totalPercentUsed: PercentUsed,
        resetsAt: Date? = nil
    ) {
        self.autoPercentUsed = autoPercentUsed
        self.apiPercentUsed = apiPercentUsed
        self.totalPercentUsed = totalPercentUsed
        self.resetsAt = resetsAt
    }

    /// Exhausted when Cursor Models, Other Models, or total hits/exceeds 100%.
    public var isExhausted: Bool {
        autoPercentUsed.isExhausted
            || apiPercentUsed.isExhausted
            || totalPercentUsed.isExhausted
    }
}

/// User-facing pool names. Internal wire fields stay auto/api.
public enum UsagePoolLabel: String, Sendable, Equatable, Hashable {
    case cursorModels = "Cursor Models"
    case otherModels = "Other Models"

    public var title: String { rawValue }

    /// Compact root-menu form. Full `title` stays in submenu and Dashboard.
    public var compactTitle: String {
        switch self {
        case .cursorModels: "Cursor"
        case .otherModels: "Other"
        }
    }
}

/// Period payload beyond the three percents. Spend fields stay opaque.
public struct PeriodUsageDetail: Codable, Sendable, Equatable, Hashable {
    public let usage: PeriodUsage
    public let billingCycleStart: Date?
    public let displayMessage: String?
    public let autoPercentDisplayMessage: String?
    public let apiPercentDisplayMessage: String?
    public let spendLimitUsage: SpendLimitUsage?

    public init(
        usage: PeriodUsage,
        billingCycleStart: Date? = nil,
        displayMessage: String? = nil,
        autoPercentDisplayMessage: String? = nil,
        apiPercentDisplayMessage: String? = nil,
        spendLimitUsage: SpendLimitUsage? = nil
    ) {
        self.usage = usage
        self.billingCycleStart = billingCycleStart
        self.displayMessage = displayMessage
        self.autoPercentDisplayMessage = autoPercentDisplayMessage
        self.apiPercentDisplayMessage = apiPercentDisplayMessage
        self.spendLimitUsage = spendLimitUsage
    }
}

/// Spend-limit slice of GetCurrentPeriodUsage.
/// Personal `individual*` fields are cents. Team fields stay opaque.
public struct SpendLimitUsage: Codable, Sendable, Equatable, Hashable {
    public let individualUsed: AmountCents?
    public let individualLimit: AmountCents?
    public let teamUsed: OpaqueAccountingUnits?
    public let teamLimit: OpaqueAccountingUnits?

    public init(
        individualUsed: AmountCents? = nil,
        individualLimit: AmountCents? = nil,
        teamUsed: OpaqueAccountingUnits? = nil,
        teamLimit: OpaqueAccountingUnits? = nil
    ) {
        self.individualUsed = individualUsed
        self.individualLimit = individualLimit
        self.teamUsed = teamUsed
        self.teamLimit = teamLimit
    }
}

public enum PlanOwner: Codable, Sendable, Equatable, Hashable {
    case personal
    case team
    case unknown(String)

    public init(wire: String) {
        switch wire.lowercased() {
        case "personal", "plan_owner_personal", "planownerpersonal":
            self = .personal
        case "team", "plan_owner_team", "planownerteam":
            self = .team
        default:
            self = .unknown(wire)
        }
    }
}

public struct PlanInfo: Codable, Sendable, Equatable, Hashable {
    public let name: String
    public let includedAmountCents: AmountCents?
    public let price: String?
    public let billingCycleEnd: Date?
    public let planOwner: PlanOwner?

    public init(
        name: String,
        includedAmountCents: AmountCents? = nil,
        price: String? = nil,
        billingCycleEnd: Date? = nil,
        planOwner: PlanOwner? = nil
    ) {
        self.name = name
        self.includedAmountCents = includedAmountCents
        self.price = price
        self.billingCycleEnd = billingCycleEnd
        self.planOwner = planOwner
    }
}

/// On-demand mode plus personal used cents when present.
public struct OnDemandState: Codable, Sendable, Equatable, Hashable {
    public let mode: OnDemandMode
    public let individualUsed: AmountCents?
    /// Cross-check / display fallback. Fixed cap still comes from `GetHardLimit` dollars.
    public let individualLimit: AmountCents?

    public init(
        mode: OnDemandMode,
        individualUsed: AmountCents? = nil,
        individualLimit: AmountCents? = nil
    ) {
        self.mode = mode
        self.individualUsed = individualUsed
        self.individualLimit = individualLimit
    }

    public var isConsuming: Bool {
        switch mode {
        case .off:
            return false
        case .fixed, .unlimited:
            return (individualUsed?.cents ?? 0) > 0
        }
    }
}

/// Credit grants balance. Empty Connect `{}` maps to `absent`, not silent zeros.
public enum CreditBalance: Codable, Sendable, Equatable, Hashable {
    /// Wire returned an empty object / omitted grant fields. Product: no grants to show.
    case absent
    case present(balance: AmountCents, total: AmountCents, used: AmountCents)
}

/// Sparse usage-limit policy. Missing fields stay nil.
public struct UsagePolicy: Codable, Sendable, Equatable, Hashable {
    public let canConfigureSpendLimit: Bool?
    public let canAdjustOnDemand: Bool?
    public let recommendedLimitCents: AmountCents?
    public let minLimitCents: AmountCents?
    public let maxLimitCents: AmountCents?
    public let currentLimitCents: AmountCents?

    public init(
        canConfigureSpendLimit: Bool? = nil,
        canAdjustOnDemand: Bool? = nil,
        recommendedLimitCents: AmountCents? = nil,
        minLimitCents: AmountCents? = nil,
        maxLimitCents: AmountCents? = nil,
        currentLimitCents: AmountCents? = nil
    ) {
        self.canConfigureSpendLimit = canConfigureSpendLimit
        self.canAdjustOnDemand = canAdjustOnDemand
        self.recommendedLimitCents = recommendedLimitCents
        self.minLimitCents = minLimitCents
        self.maxLimitCents = maxLimitCents
        self.currentLimitCents = currentLimitCents
    }

    /// Live Ultra personal accounts often return only `canConfigureSpendLimit`.
    public var allowsOnDemandAdjust: Bool {
        if let canAdjustOnDemand { return canAdjustOnDemand }
        if let canConfigureSpendLimit { return canConfigureSpendLimit }
        return false
    }
}
