import CursorBarDomain
import Foundation

struct GetUsageLimitPolicyStatusWireDTO: Decodable, Sendable {
    var canConfigureSpendLimit: Bool?
    var canAdjustOnDemand: Bool?
    var recommendedLimitCents: FlexibleInt64?
    var minLimitCents: FlexibleInt64?
    var maxLimitCents: FlexibleInt64?
    var currentLimitCents: FlexibleInt64?
}

enum DashboardPolicyWire {
    static func policy(from dto: GetUsageLimitPolicyStatusWireDTO) throws -> UsagePolicy {
        UsagePolicy(
            canConfigureSpendLimit: dto.canConfigureSpendLimit,
            canAdjustOnDemand: dto.canAdjustOnDemand,
            recommendedLimitCents: dto.recommendedLimitCents.map { AmountCents(cents: $0.value) },
            minLimitCents: dto.minLimitCents.map { AmountCents(cents: $0.value) },
            maxLimitCents: dto.maxLimitCents.map { AmountCents(cents: $0.value) },
            currentLimitCents: dto.currentLimitCents.map { AmountCents(cents: $0.value) }
        )
    }
}
