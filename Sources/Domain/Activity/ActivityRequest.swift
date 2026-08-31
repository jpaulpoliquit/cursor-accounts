import Foundation

/// Canonical token sum for activity metrics. Same four buckets as Aggregate summaries.
public struct TokenBreakdown: Sendable, Equatable, Hashable {
    public let input: Int64
    public let output: Int64
    public let cacheWrite: Int64
    public let cacheRead: Int64

    public init(input: Int64, output: Int64, cacheWrite: Int64, cacheRead: Int64) {
        self.input = max(0, input)
        self.output = max(0, output)
        self.cacheWrite = max(0, cacheWrite)
        self.cacheRead = max(0, cacheRead)
    }

    public var total: Int64 {
        input + output + cacheWrite + cacheRead
    }

    public var asBuckets: TokenBucketCounts {
        TokenBucketCounts(input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
            ?? .zero
    }
}

/// Idle-gap policy for estimated agent-active time. Default 30 minutes.
public struct IdleGapPolicy: Sendable, Equatable, Hashable, Codable {
    public let maxGapMs: Int64

    public init(maxGapMs: Int64) {
        precondition(maxGapMs > 0)
        self.maxGapMs = maxGapMs
    }

    public static let thirtyMinutes = IdleGapPolicy(maxGapMs: 30 * 60 * 1000)

    public var accessibilityLabel: String {
        let minutes = maxGapMs / 60_000
        return "Estimated agent-active time. Each gap between requests is capped at \(minutes) minutes."
    }

    public var methodologyCopy: String {
        let minutes = maxGapMs / 60_000
        return "Each gap between requests is capped at \(minutes) minutes."
    }
}

/// One usage display event after wire decode. Never carries raw conversation IDs or emails.
public struct ActivityRequest: Sendable, Equatable, Hashable {
    public let timestampMs: Int64
    public let model: String
    public let kind: BillingKind
    public let tokens: TokenBreakdown?
    /// Computed usage value cents (`chargedCents` / tokenUsage.totalCents). Not billed on-demand.
    public let usageValueCents: Int64?
    /// Parsed on-demand charged cents from `usageBasedCosts` dollar string. Nil when absent/"-".
    public let onDemandChargedCents: Int64?
    public let isHeadless: Bool
    public let isTokenBasedCall: Bool
    public let clientType: String?
    public let hasCloudAgent: Bool
    public let hasAutomation: Bool

    public init(
        timestampMs: Int64,
        model: String,
        kind: BillingKind,
        tokens: TokenBreakdown?,
        usageValueCents: Int64?,
        onDemandChargedCents: Int64?,
        isHeadless: Bool,
        isTokenBasedCall: Bool,
        clientType: String? = nil,
        hasCloudAgent: Bool = false,
        hasAutomation: Bool = false
    ) {
        self.timestampMs = timestampMs
        self.model = model
        self.kind = kind
        self.tokens = tokens
        self.usageValueCents = usageValueCents
        self.onDemandChargedCents = onDemandChargedCents
        self.isHeadless = isHeadless
        self.isTokenBasedCall = isTokenBasedCall
        self.clientType = clientType
        self.hasCloudAgent = hasCloudAgent
        self.hasAutomation = hasAutomation
    }
}
