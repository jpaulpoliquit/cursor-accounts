import CursorBarDomain
import Foundation

struct GetPlanInfoWireDTO: Decodable, Sendable {
    var planInfo: PlanInfoWireDTO?
}

struct PlanInfoWireDTO: Decodable, Sendable {
    var planName: String?
    var includedAmountCents: Int32?
    var price: String?
    var billingCycleEnd: String?
    var planOwner: String?
}

enum DashboardPlanWire {
    static func planInfo(from dto: GetPlanInfoWireDTO) throws -> PlanInfo {
        guard let info = dto.planInfo else {
            throw DashboardWireCodec.DecodeError.missingPlanName
        }
        guard let name = info.planName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            throw DashboardWireCodec.DecodeError.missingPlanName
        }
        let included: AmountCents?
        if let cents = info.includedAmountCents {
            included = AmountCents(cents: Int64(cents))
        } else {
            included = nil
        }
        let end: Date?
        if let raw = info.billingCycleEnd {
            guard let date = DashboardWireCodec.millisDate(fromDecimalString: raw) else {
                throw DashboardWireCodec.DecodeError.invalidBillingCycleEnd
            }
            end = date
        } else {
            end = nil
        }
        let owner = info.planOwner.map(PlanOwner.init(wire:))
        return PlanInfo(
            name: name,
            includedAmountCents: included,
            price: info.price,
            billingCycleEnd: end,
            planOwner: owner
        )
    }
}
