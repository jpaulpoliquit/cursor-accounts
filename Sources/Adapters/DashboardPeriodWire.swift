import CursorBarDomain
import Foundation

struct GetCurrentPeriodUsageWireDTO: Decodable, Sendable {
    var billingCycleStart: String?
    var billingCycleEnd: String?
    var planUsage: PlanUsageWireDTO?
    var spendLimitUsage: SpendLimitUsageWireDTO?
    var displayMessage: String?
    var autoPercentDisplayMessage: String?
    var apiPercentDisplayMessage: String?
    var autoModelSelectedDisplayMessage: String?
    var namedModelSelectedDisplayMessage: String?
}

struct PlanUsageWireDTO: Decodable, Sendable {
    var autoPercentUsed: Double?
    var apiPercentUsed: Double?
    var totalPercentUsed: Double?
}

struct SpendLimitUsageWireDTO: Decodable, Sendable {
    var individualUsed: FlexibleInt64?
    var individualLimit: FlexibleInt64?
    var teamUsed: FlexibleInt64?
    var teamLimit: FlexibleInt64?
    var totalSpend: FlexibleInt64?
}

enum DashboardPeriodWire {
    static func detail(from dto: GetCurrentPeriodUsageWireDTO) throws -> PeriodUsageDetail {
        guard let plan = dto.planUsage else {
            throw DashboardWireCodec.DecodeError.missingPlanUsage
        }
        guard let autoRaw = plan.autoPercentUsed else {
            throw DashboardWireCodec.DecodeError.missingRequiredPercent("autoPercentUsed")
        }
        guard let apiRaw = plan.apiPercentUsed else {
            throw DashboardWireCodec.DecodeError.missingRequiredPercent("apiPercentUsed")
        }
        guard let totalRaw = plan.totalPercentUsed else {
            throw DashboardWireCodec.DecodeError.missingRequiredPercent("totalPercentUsed")
        }

        let usage = PeriodUsage(
            autoPercentUsed: try DashboardWireCodec.percent(autoRaw, field: "autoPercentUsed"),
            apiPercentUsed: try DashboardWireCodec.percent(apiRaw, field: "apiPercentUsed"),
            totalPercentUsed: try DashboardWireCodec.percent(totalRaw, field: "totalPercentUsed"),
            resetsAt: try optionalMillis(dto.billingCycleEnd, error: .invalidBillingCycleEnd)
        )

        return PeriodUsageDetail(
            usage: usage,
            billingCycleStart: try optionalMillis(dto.billingCycleStart, error: .invalidBillingCycleStart),
            displayMessage: dto.displayMessage,
            autoPercentDisplayMessage: dto.autoPercentDisplayMessage ?? dto.autoModelSelectedDisplayMessage,
            apiPercentDisplayMessage: dto.apiPercentDisplayMessage ?? dto.namedModelSelectedDisplayMessage,
            spendLimitUsage: spendLimit(from: dto.spendLimitUsage)
        )
    }

    private static func optionalMillis(
        _ raw: String?,
        error: DashboardWireCodec.DecodeError
    ) throws -> Date? {
        guard let raw else { return nil }
        guard let date = DashboardWireCodec.millisDate(fromDecimalString: raw) else {
            throw error
        }
        return date
    }

    private static func spendLimit(from dto: SpendLimitUsageWireDTO?) -> SpendLimitUsage? {
        guard let dto else { return nil }
        // Personal individual* fields are cents. Ignore planUsage.totalSpend / dto.totalSpend.
        let individualUsed = dto.individualUsed.map { AmountCents(cents: $0.value) }
        let individualLimit = dto.individualLimit.map { AmountCents(cents: $0.value) }
        let teamUsed = dto.teamUsed.map { OpaqueAccountingUnits(raw: $0.value) }
        let teamLimit = dto.teamLimit.map { OpaqueAccountingUnits(raw: $0.value) }
        if individualUsed == nil, individualLimit == nil, teamUsed == nil, teamLimit == nil {
            return nil
        }
        return SpendLimitUsage(
            individualUsed: individualUsed,
            individualLimit: individualLimit,
            teamUsed: teamUsed,
            teamLimit: teamLimit
        )
    }
}
