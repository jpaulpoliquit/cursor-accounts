import CursorBarDomain
import Foundation

struct GetCreditGrantsBalanceWireDTO: Decodable, Sendable {
    var creditBalanceCents: FlexibleInt64?
    var totalCents: FlexibleInt64?
    var usedCents: FlexibleInt64?
}

enum DashboardCreditsWire {
    /// Empty `{}` (all grant fields omitted) is product `CreditBalance.absent`, not silent zeros.
    static func balance(from dto: GetCreditGrantsBalanceWireDTO) throws -> CreditBalance {
        let hasAny =
            dto.creditBalanceCents != nil
            || dto.totalCents != nil
            || dto.usedCents != nil
        guard hasAny else { return .absent }

        guard let balance = dto.creditBalanceCents else {
            throw DashboardWireCodec.DecodeError.invalidCreditCents("creditBalanceCents")
        }
        guard let total = dto.totalCents else {
            throw DashboardWireCodec.DecodeError.invalidCreditCents("totalCents")
        }
        guard let used = dto.usedCents else {
            throw DashboardWireCodec.DecodeError.invalidCreditCents("usedCents")
        }
        return .present(
            balance: AmountCents(cents: balance.value),
            total: AmountCents(cents: total.value),
            used: AmountCents(cents: used.value)
        )
    }
}
