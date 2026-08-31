import CursorBarDomain
import Foundation

struct GetAggregatedUsageEventsWireBody: Encodable, Sendable {
    var startDate: Int64
    var endDate: Int64
}

struct GetAggregatedUsageEventsWireDTO: Decodable, Sendable {
    var aggregations: [ModelUsageAggregationWireDTO]?
    var totalInputTokens: FlexibleInt64?
    var totalOutputTokens: FlexibleInt64?
    var totalCacheWriteTokens: FlexibleInt64?
    var totalCacheReadTokens: FlexibleInt64?
    var totalCostCents: Double?
    var percentOfBurstUsed: Double?
    var totalRequestCost: Double?
}

struct ModelUsageAggregationWireDTO: Decodable, Sendable {
    var modelIntent: String?
    var inputTokens: FlexibleInt64?
    var outputTokens: FlexibleInt64?
    var cacheWriteTokens: FlexibleInt64?
    var cacheReadTokens: FlexibleInt64?
    var totalCents: Double?
    var requestCost: Double?
    var tier: FlexibleInt32?
}

enum DashboardAggregatedUsageWire {
    static func encodeRequest(startDateMs: Int64, endDateMs: Int64) throws -> Data {
        let body = GetAggregatedUsageEventsWireBody(startDate: startDateMs, endDate: endDateMs)
        return try JSONEncoder().encode(body)
    }

    static func summary(from dto: GetAggregatedUsageEventsWireDTO, seatID: SeatID) throws -> SeatUsageTokenSummary {
        let totals = try buckets(
            input: dto.totalInputTokens?.value ?? 0,
            output: dto.totalOutputTokens?.value ?? 0,
            cacheWrite: dto.totalCacheWriteTokens?.value ?? 0,
            cacheRead: dto.totalCacheReadTokens?.value ?? 0,
            field: "totals"
        )
        let models = try (dto.aggregations ?? []).map { row in
            try modelRow(from: row)
        }
        return SeatUsageTokenSummary(seatID: seatID, totals: totals, models: models)
    }

    private static func modelRow(from dto: ModelUsageAggregationWireDTO) throws -> ModelUsageRow {
        let intent = (dto.modelIntent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !intent.isEmpty else {
            throw DashboardWireCodec.DecodeError.invalidTokenBuckets("modelIntent")
        }
        let buckets = try buckets(
            input: dto.inputTokens?.value ?? 0,
            output: dto.outputTokens?.value ?? 0,
            cacheWrite: dto.cacheWriteTokens?.value ?? 0,
            cacheRead: dto.cacheReadTokens?.value ?? 0,
            field: intent
        )
        return ModelUsageRow(
            modelIntent: intent,
            displayName: ModelDisplayNames.displayName(for: intent),
            buckets: buckets
        )
    }

    private static func buckets(
        input: Int64,
        output: Int64,
        cacheWrite: Int64,
        cacheRead: Int64,
        field: String
    ) throws -> TokenBucketCounts {
        guard let buckets = TokenBucketCounts(
            input: input,
            output: output,
            cacheWrite: cacheWrite,
            cacheRead: cacheRead
        ) else {
            throw DashboardWireCodec.DecodeError.invalidTokenBuckets(field)
        }
        return buckets
    }
}
