import CursorBarDomain
import Foundation

struct GetFilteredUsageEventsWireBody: Encodable, Sendable {
    var startDate: Int64
    var endDate: Int64
    var page: Int32
    var pageSize: Int32
}

struct GetFilteredUsageEventsWireDTO: Decodable, Sendable {
    var usageEventsDisplay: [UsageEventDisplayWireDTO]?
    var usageEvents: [UsageEventRawWireDTO]?
    var totalUsageEventsCount: FlexibleInt32?
}

/// Raw events are ignored for Insights; present so empty arrays decode cleanly.
struct UsageEventRawWireDTO: Decodable, Sendable {}

struct UsageEventDisplayWireDTO: Decodable, Sendable {
    var timestamp: FlexibleInt64?
    var model: String?
    var kind: String?
    var usageBasedCosts: String?
    var isTokenBasedCall: Bool?
    var tokenUsage: UsageEventTokenUsageWireDTO?
    var cursorTokenFee: Double?
    var isChargeable: Bool?
    var serviceAccountId: String?
    var isHeadless: Bool?
    var chargedCents: Double?
    var conversationId: String?
    var cloudAgentId: String?
    var automationId: String?
    var automationManagedType: String?
    var clientType: String?
    var requestsCosts: Double?
    var subscriptionProductId: String?
    var userEmail: String?
    var owningUser: String?
    var owningTeam: String?
}

struct UsageEventTokenUsageWireDTO: Decodable, Sendable {
    var inputTokens: FlexibleInt64?
    var outputTokens: FlexibleInt64?
    var cacheWriteTokens: FlexibleInt64?
    var cacheReadTokens: FlexibleInt64?
    var totalCents: Double?
}

enum DashboardUsageEventsWire {
    static let defaultPageSize = DashboardClient.filteredUsageEventsPageSize

    static func encodeRequest(
        startDateMs: Int64,
        endDateMs: Int64,
        page: Int32,
        pageSize: Int32 = defaultPageSize
    ) throws -> Data {
        let body = GetFilteredUsageEventsWireBody(
            startDate: startDateMs,
            endDate: endDateMs,
            page: page,
            pageSize: pageSize
        )
        return try JSONEncoder().encode(body)
    }

    /// Maps display rows to domain requests. Drops conversation IDs, emails, and owning ids.
    static func requests(from dto: GetFilteredUsageEventsWireDTO) throws -> (
        requests: [ActivityRequest],
        totalCount: Int
    ) {
        let total = Int(dto.totalUsageEventsCount?.value ?? 0)
        let rows = dto.usageEventsDisplay ?? []
        var parsed: [ActivityRequest] = []
        parsed.reserveCapacity(rows.count)
        for row in rows {
            guard let timestamp = row.timestamp?.value else {
                throw DashboardWireCodec.DecodeError.invalidTokenBuckets("timestamp")
            }
            let model = (row.model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens: TokenBreakdown?
            if let usage = row.tokenUsage {
                tokens = TokenBreakdown(
                    input: usage.inputTokens?.value ?? 0,
                    output: usage.outputTokens?.value ?? 0,
                    cacheWrite: usage.cacheWriteTokens?.value ?? 0,
                    cacheRead: usage.cacheReadTokens?.value ?? 0
                )
            } else {
                tokens = nil
            }
            let client = row.clientType?.trimmingCharacters(in: .whitespacesAndNewlines)
            let usageValue = ActivityCostSemantics.usageValueCents(fromChargedCents: row.chargedCents)
                ?? ActivityCostSemantics.usageValueCents(fromChargedCents: row.tokenUsage?.totalCents)
            parsed.append(
                ActivityRequest(
                    timestampMs: timestamp,
                    model: model.isEmpty ? "unknown" : model,
                    kind: BillingKind(wireName: row.kind),
                    tokens: tokens,
                    usageValueCents: usageValue,
                    onDemandChargedCents: ActivityCostSemantics.onDemandChargedCents(
                        fromUsageBasedCosts: row.usageBasedCosts
                    ),
                    isHeadless: row.isHeadless ?? false,
                    isTokenBasedCall: row.isTokenBasedCall ?? false,
                    clientType: (client?.isEmpty == false) ? client : nil,
                    hasCloudAgent: !(row.cloudAgentId ?? "").isEmpty,
                    hasAutomation: !(row.automationId ?? "").isEmpty
                        || !(row.automationManagedType ?? "").isEmpty
                )
            )
        }
        return (parsed, total)
    }
}
