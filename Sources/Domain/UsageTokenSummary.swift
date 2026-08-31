import Foundation

/// Disjoint token buckets from GetAggregatedUsageEvents. Canonical total is the sum of all four.
public struct TokenBucketCounts: Sendable, Equatable, Hashable, Codable {
    public let input: Int64
    public let output: Int64
    public let cacheWrite: Int64
    public let cacheRead: Int64
    public let total: Int64

    public init?(input: Int64, output: Int64, cacheWrite: Int64, cacheRead: Int64) {
        guard input >= 0, output >= 0, cacheWrite >= 0, cacheRead >= 0 else { return nil }
        let (sumIO, overflowIO) = input.addingReportingOverflow(output)
        guard !overflowIO else { return nil }
        let (sumIOW, overflowIOW) = sumIO.addingReportingOverflow(cacheWrite)
        guard !overflowIOW else { return nil }
        let (sumAll, overflowAll) = sumIOW.addingReportingOverflow(cacheRead)
        guard !overflowAll else { return nil }
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
        self.total = sumAll
    }

    public static let zero = TokenBucketCounts(input: 0, output: 0, cacheWrite: 0, cacheRead: 0)!

    public func adding(_ other: TokenBucketCounts) -> TokenBucketCounts? {
        let (input, o1) = self.input.addingReportingOverflow(other.input)
        guard !o1 else { return nil }
        let (output, o2) = self.output.addingReportingOverflow(other.output)
        guard !o2 else { return nil }
        let (cacheWrite, o3) = self.cacheWrite.addingReportingOverflow(other.cacheWrite)
        guard !o3 else { return nil }
        let (cacheRead, o4) = self.cacheRead.addingReportingOverflow(other.cacheRead)
        guard !o4 else { return nil }
        return TokenBucketCounts(input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
    }

    enum CodingKeys: String, CodingKey {
        case input, output, cacheWrite, cacheRead
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let input = try container.decode(Int64.self, forKey: .input)
        let output = try container.decode(Int64.self, forKey: .output)
        let cacheWrite = try container.decode(Int64.self, forKey: .cacheWrite)
        let cacheRead = try container.decode(Int64.self, forKey: .cacheRead)
        guard let built = TokenBucketCounts(
            input: input,
            output: output,
            cacheWrite: cacheWrite,
            cacheRead: cacheRead
        ) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "invalid token buckets"
                )
            )
        }
        self = built
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(input, forKey: .input)
        try container.encode(output, forKey: .output)
        try container.encode(cacheWrite, forKey: .cacheWrite)
        try container.encode(cacheRead, forKey: .cacheRead)
    }
}

/// One model’s absolute token buckets. Share is never stored here.
public struct ModelUsageRow: Sendable, Equatable, Hashable, Codable {
    public let modelIntent: String
    public let displayName: String
    public let buckets: TokenBucketCounts

    public init(modelIntent: String, displayName: String, buckets: TokenBucketCounts) {
        self.modelIntent = modelIntent
        self.displayName = displayName
        self.buckets = buckets
    }
}

/// Top-model presentation row. Share is absolute against the summary total, never averaged.
public struct RankedModelUsage: Sendable, Equatable, Hashable, Codable {
    public let model: ModelUsageRow
    public let share: Double

    public init(model: ModelUsageRow, share: Double) {
        self.model = model
        self.share = share
    }
}

/// Per-seat aggregate decode before multi-seat merge. Keeps the full model list.
public struct SeatUsageTokenSummary: Sendable, Equatable, Hashable {
    public let seatID: SeatID
    public let totals: TokenBucketCounts
    public let models: [ModelUsageRow]

    public init(seatID: SeatID, totals: TokenBucketCounts, models: [ModelUsageRow]) {
        self.seatID = seatID
        self.totals = totals
        self.models = models
    }
}

/// Temporal Aggregate coverage when All Time (or chunked) windows are only partially retrieved.
public struct TemporalCoverage: Sendable, Equatable, Hashable, Codable {
    public let requestedStart: UsageDayKey
    public let requestedEnd: UsageDayKey
    public let coveredStart: UsageDayKey?
    public let coveredEnd: UsageDayKey?
    public let failedChunkCount: Int

    public init(
        requestedStart: UsageDayKey,
        requestedEnd: UsageDayKey,
        coveredStart: UsageDayKey?,
        coveredEnd: UsageDayKey?,
        failedChunkCount: Int
    ) {
        self.requestedStart = requestedStart
        self.requestedEnd = requestedEnd
        self.coveredStart = coveredStart
        self.coveredEnd = coveredEnd
        self.failedChunkCount = failedChunkCount
    }

    public var isComplete: Bool {
        failedChunkCount == 0
            && coveredStart == requestedStart
            && coveredEnd == requestedEnd
    }

    public var caption: String? {
        guard !isComplete else { return nil }
        if let coveredStart {
            return "Totals from \(coveredStart.isoDate) (partial history)"
        }
        return "Token totals partially unavailable"
    }

    public static func complete(from start: UsageDayKey, through end: UsageDayKey) -> TemporalCoverage {
        TemporalCoverage(
            requestedStart: start,
            requestedEnd: end,
            coveredStart: start,
            coveredEnd: end,
            failedChunkCount: 0
        )
    }
}

/// Scope/range token summary for Dashboard cards. Totals come from Aggregate, never the daily chart.
public struct UsageTokenSummary: Sendable, Equatable, Hashable, Codable {
    public let scope: UsageScope
    public let range: UsageRange
    public let totals: TokenBucketCounts
    public let topModels: [RankedModelUsage]
    public let coverage: PartialCoverage
    public let temporalCoverage: TemporalCoverage?
    public let fetchedAt: Date

    public init(
        scope: UsageScope,
        range: UsageRange,
        totals: TokenBucketCounts,
        topModels: [RankedModelUsage],
        coverage: PartialCoverage,
        temporalCoverage: TemporalCoverage? = nil,
        fetchedAt: Date
    ) {
        self.scope = scope
        self.range = range
        self.totals = totals
        self.topModels = topModels
        self.coverage = coverage
        self.temporalCoverage = temporalCoverage
        self.fetchedAt = fetchedAt
    }
}

/// Pure ranking, share, and multi-seat merge for token summaries.
public enum UsageTokenSummaryAggregator {
    public static let topModelLimit = 5

    public static func share(modelTotal: Int64, summaryTotal: Int64) -> Double {
        guard summaryTotal > 0, modelTotal >= 0 else { return 0 }
        return Double(modelTotal) / Double(summaryTotal)
    }

    public static func rankedTopModels(
        from models: [ModelUsageRow],
        summaryTotal: Int64,
        limit: Int = topModelLimit
    ) -> [RankedModelUsage] {
        let sorted = models.sorted { lhs, rhs in
            if lhs.buckets.total != rhs.buckets.total {
                return lhs.buckets.total > rhs.buckets.total
            }
            return lhs.modelIntent < rhs.modelIntent
        }
        return Array(sorted.prefix(max(0, limit))).map { model in
            RankedModelUsage(
                model: model,
                share: share(modelTotal: model.buckets.total, summaryTotal: summaryTotal)
            )
        }
    }

    public static func aggregate(
        successful: [SeatUsageTokenSummary],
        requestedAccountCount: Int,
        scope: UsageScope,
        range: UsageRange,
        temporalCoverage: TemporalCoverage? = nil,
        fetchedAt: Date = Date()
    ) -> UsageTokenSummary {
        let coverage = PartialCoverage(
            includedAccountCount: successful.count,
            requestedAccountCount: requestedAccountCount
        )
        guard !successful.isEmpty else {
            return UsageTokenSummary(
                scope: scope,
                range: range,
                totals: .zero,
                topModels: [],
                coverage: coverage,
                temporalCoverage: temporalCoverage,
                fetchedAt: fetchedAt
            )
        }

        var totals = TokenBucketCounts.zero
        var merged: [String: TokenBucketCounts] = [:]
        var displayNames: [String: String] = [:]

        for seat in successful {
            guard let nextTotals = totals.adding(seat.totals) else {
                return UsageTokenSummary(
                    scope: scope,
                    range: range,
                    totals: .zero,
                    topModels: [],
                    coverage: coverage,
                    temporalCoverage: temporalCoverage,
                    fetchedAt: fetchedAt
                )
            }
            totals = nextTotals
            for model in seat.models {
                displayNames[model.modelIntent] = model.displayName
                if let existing = merged[model.modelIntent] {
                    guard let summed = existing.adding(model.buckets) else {
                        return UsageTokenSummary(
                            scope: scope,
                            range: range,
                            totals: .zero,
                            topModels: [],
                            coverage: coverage,
                            temporalCoverage: temporalCoverage,
                            fetchedAt: fetchedAt
                        )
                    }
                    merged[model.modelIntent] = summed
                } else {
                    merged[model.modelIntent] = model.buckets
                }
            }
        }

        let models = merged.map { intent, buckets in
            ModelUsageRow(
                modelIntent: intent,
                displayName: displayNames[intent] ?? ModelDisplayNames.displayName(for: intent),
                buckets: buckets
            )
        }
        let top = rankedTopModels(from: models, summaryTotal: totals.total)
        return UsageTokenSummary(
            scope: scope,
            range: range,
            totals: totals,
            topModels: top,
            coverage: coverage,
            temporalCoverage: temporalCoverage,
            fetchedAt: fetchedAt
        )
    }

    /// Deterministic merge of month/year Aggregate chunks for one seat. Half-open bounds; no double count.
    public static func mergeSeatChunks(_ chunks: [SeatUsageTokenSummary]) -> SeatUsageTokenSummary? {
        guard let first = chunks.first else { return nil }
        var totals = TokenBucketCounts.zero
        var merged: [String: TokenBucketCounts] = [:]
        var displayNames: [String: String] = [:]
        for chunk in chunks {
            guard chunk.seatID == first.seatID else { return nil }
            guard let next = totals.adding(chunk.totals) else { return nil }
            totals = next
            for model in chunk.models {
                displayNames[model.modelIntent] = model.displayName
                if let existing = merged[model.modelIntent] {
                    guard let summed = existing.adding(model.buckets) else { return nil }
                    merged[model.modelIntent] = summed
                } else {
                    merged[model.modelIntent] = model.buckets
                }
            }
        }
        let models = merged.map { intent, buckets in
            ModelUsageRow(
                modelIntent: intent,
                displayName: displayNames[intent] ?? ModelDisplayNames.displayName(for: intent),
                buckets: buckets
            )
        }
        return SeatUsageTokenSummary(seatID: first.seatID, totals: totals, models: models)
    }
}
