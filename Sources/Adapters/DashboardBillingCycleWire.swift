import CursorBarDomain
import Foundation

struct GetMonthlyBillingCycleWireDTO: Decodable, Sendable {
    var startDateEpochMillis: FlexibleInt64?
    var endDateEpochMillis: FlexibleInt64?
}

enum DashboardBillingCycleWire {
    static func bounds(from dto: GetMonthlyBillingCycleWireDTO) throws -> BillingCycleBounds {
        guard let start = dto.startDateEpochMillis?.value else {
            throw DashboardWireCodec.DecodeError.invalidBillingCycleStart
        }
        guard let end = dto.endDateEpochMillis?.value else {
            throw DashboardWireCodec.DecodeError.invalidBillingCycleEnd
        }
        return BillingCycleBounds(startMs: start, endMs: end)
    }
}
