import CursorBarDomain
import Foundation

struct GetDailySpendByCategoryWireBody: Encodable, Sendable {
    var periodStartMs: Int64
    var periodEndMs: Int64
    var groupBy: String
    var spendType: String
}

struct GetDailySpendByCategoryWireDTO: Decodable, Sendable {
    var dailySpend: [DailySpendByCategoryWireDTO]?
    var categories: [String]?
    var effectiveLimitCents: FlexibleInt32?
}

struct DailySpendByCategoryWireDTO: Decodable, Sendable {
    var day: FlexibleInt64?
    var category: String?
    var spendCents: FlexibleInt32?
    var totalTokens: FlexibleInt64?
}

enum DashboardDailySpendWire {
    static let groupByModel = "MODEL"
    static let spendTypeAll = "ALL"

    static func encodeRequest(periodStartMs: Int64, periodEndMs: Int64) throws -> Data {
        let body = GetDailySpendByCategoryWireBody(
            periodStartMs: periodStartMs,
            periodEndMs: periodEndMs,
            groupBy: groupByModel,
            spendType: spendTypeAll
        )
        return try JSONEncoder().encode(body)
    }

    static func rows(from dto: GetDailySpendByCategoryWireDTO) throws -> [DailySpendCategoryRow] {
        guard let daily = dto.dailySpend else { return [] }
        return try daily.map { row in
            guard let dayMs = row.day?.value else {
                throw DashboardWireCodec.DecodeError.invalidBillingCycleStart
            }
            guard let tokens = row.totalTokens?.value else {
                throw DashboardWireCodec.DecodeError.invalidSpendUnits("totalTokens")
            }
            return DailySpendCategoryRow(
                day: UsageDayKey.utcDay(midnightMs: dayMs),
                category: row.category ?? "",
                spendCents: row.spendCents?.value,
                totalTokens: tokens
            )
        }
    }
}
