import CursorBarDomain
import Foundation

/// Single DashboardService adapter. Typed methods share one Connect transport.
public struct DashboardClient: Sendable {
    public enum ClientError: Error, Sendable, Equatable {
        case transport(DashboardConnectTransport.TransportError)
        case decode
        case invalidHardLimit
    }

    private let transport: DashboardConnectTransport

    public init(transport: DashboardConnectTransport = DashboardConnectTransport()) {
        self.transport = transport
    }

    public init(exchange: @escaping DashboardConnectTransport.Exchange) {
        self.transport = DashboardConnectTransport(exchange: exchange)
    }

    public func getPlanInfo(access: ConnectReadyAccessToken) async throws -> PlanInfo {
        let data = try await post(method: "GetPlanInfo", access: access)
        do {
            let dto = try JSONDecoder().decode(GetPlanInfoWireDTO.self, from: data)
            return try DashboardPlanWire.planInfo(from: dto)
        } catch is DashboardWireCodec.DecodeError {
            throw ClientError.decode
        } catch {
            throw ClientError.decode
        }
    }

    /// Stable account identity for the session JWT. Body is `{}` (personal).
    public func getMe(access: ConnectReadyAccessToken) async throws -> HydratedAccountIdentity {
        try await getMeProfile(access: access).identity
    }

    /// Identity plus optional account `createdAt` for history bounds (not earliest usage).
    public func getMeProfile(access: ConnectReadyAccessToken) async throws -> GetMeProfile {
        let data = try await post(method: "GetMe", access: access)
        do {
            let dto = try JSONDecoder().decode(GetMeWireDTO.self, from: data)
            return try DashboardGetMeWire.profile(from: dto)
        } catch is DashboardWireCodec.DecodeError {
            throw ClientError.decode
        } catch {
            throw ClientError.decode
        }
    }

    public func getCurrentPeriodUsage(access: ConnectReadyAccessToken) async throws -> PeriodUsageDetail {
        let data = try await post(method: "GetCurrentPeriodUsage", access: access)
        return try Self.parsePeriodUsage(data)
    }

    public func getHardLimit(access: ConnectReadyAccessToken) async throws -> HardLimit {
        let data = try await post(method: "GetHardLimit", access: access)
        do {
            let dto = try JSONDecoder().decode(GetHardLimitWireDTO.self, from: data)
            return try DashboardHardLimitWire.hardLimit(from: dto)
        } catch DashboardWireCodec.DecodeError.invalidHardLimit {
            throw ClientError.invalidHardLimit
        } catch {
            throw ClientError.decode
        }
    }

    public func setHardLimit(access: ConnectReadyAccessToken, mode: OnDemandMode) async throws {
        let body = try DashboardHardLimitWire.encodeSetBody(mode: mode)
        _ = try await post(method: "SetHardLimit", access: access, body: body)
    }

    public func getCreditGrantsBalance(access: ConnectReadyAccessToken) async throws -> CreditBalance {
        let data = try await post(method: "GetCreditGrantsBalance", access: access)
        do {
            let dto = try JSONDecoder().decode(GetCreditGrantsBalanceWireDTO.self, from: data)
            return try DashboardCreditsWire.balance(from: dto)
        } catch is DashboardWireCodec.DecodeError {
            throw ClientError.decode
        } catch {
            throw ClientError.decode
        }
    }

    public func getUsageLimitPolicyStatus(access: ConnectReadyAccessToken) async throws -> UsagePolicy {
        let data = try await post(method: "GetUsageLimitPolicyStatus", access: access)
        do {
            let dto = try JSONDecoder().decode(GetUsageLimitPolicyStatusWireDTO.self, from: data)
            return try DashboardPolicyWire.policy(from: dto)
        } catch is DashboardWireCodec.DecodeError {
            throw ClientError.decode
        } catch {
            throw ClientError.decode
        }
    }

    /// Personal billing cycle bounds. Body is `{}`. Never send `teamId: 0`.
    public func getMonthlyBillingCycle(access: ConnectReadyAccessToken) async throws -> BillingCycleBounds {
        let data = try await post(method: "GetMonthlyBillingCycle", access: access)
        do {
            let dto = try JSONDecoder().decode(GetMonthlyBillingCycleWireDTO.self, from: data)
            return try DashboardBillingCycleWire.bounds(from: dto)
        } catch is DashboardWireCodec.DecodeError {
            throw ClientError.decode
        } catch {
            throw ClientError.decode
        }
    }

    /// Daily category×day rows for the graph. Personal: omit teamId.
    public func getDailySpendByCategory(
        access: ConnectReadyAccessToken,
        periodStartMs: Int64,
        periodEndMs: Int64
    ) async throws -> [DailySpendCategoryRow] {
        let body = try DashboardDailySpendWire.encodeRequest(
            periodStartMs: periodStartMs,
            periodEndMs: periodEndMs
        )
        let data = try await post(method: "GetDailySpendByCategory", access: access, body: body)
        do {
            let dto = try JSONDecoder().decode(GetDailySpendByCategoryWireDTO.self, from: data)
            return try DashboardDailySpendWire.rows(from: dto)
        } catch is DashboardWireCodec.DecodeError {
            throw ClientError.decode
        } catch {
            throw ClientError.decode
        }
    }

    /// Token totals and per-model aggregations for summary cards. Personal: omit teamId and userId.
    public func getAggregatedUsageEvents(
        access: ConnectReadyAccessToken,
        startDateMs: Int64,
        endDateMs: Int64,
        seatID: SeatID = .seat1
    ) async throws -> SeatUsageTokenSummary {
        let body = try DashboardAggregatedUsageWire.encodeRequest(
            startDateMs: startDateMs,
            endDateMs: endDateMs
        )
        let data = try await post(method: "GetAggregatedUsageEvents", access: access, body: body)
        do {
            let dto = try JSONDecoder().decode(GetAggregatedUsageEventsWireDTO.self, from: data)
            return try DashboardAggregatedUsageWire.summary(from: dto, seatID: seatID)
        } catch is DashboardWireCodec.DecodeError {
            throw ClientError.decode
        } catch {
            throw ClientError.decode
        }
    }

    /// DashboardService max. 1001+ returns HTTP 400 (`pageSize cannot exceed 1000`).
    public static let filteredUsageEventsPageSize: Int32 = 1000

    /// One page of usage display events. Personal: omit teamId and userId. Newest-first.
    public func getFilteredUsageEventsPage(
        access: ConnectReadyAccessToken,
        startDateMs: Int64,
        endDateMs: Int64,
        page: Int32,
        pageSize: Int32 = DashboardClient.filteredUsageEventsPageSize
    ) async throws -> (requests: [ActivityRequest], totalCount: Int) {
        let body = try DashboardUsageEventsWire.encodeRequest(
            startDateMs: startDateMs,
            endDateMs: endDateMs,
            page: page,
            pageSize: pageSize
        )
        let data = try await post(method: "GetFilteredUsageEvents", access: access, body: body)
        do {
            let dto = try JSONDecoder().decode(GetFilteredUsageEventsWireDTO.self, from: data)
            return try DashboardUsageEventsWire.requests(from: dto)
        } catch is DashboardWireCodec.DecodeError {
            throw ClientError.decode
        } catch {
            throw ClientError.decode
        }
    }

    /// Fetches the five read RPCs for one seat and assembles a cohesive snapshot.
    public func fetchSeatUsage(seatID: SeatID, access: ConnectReadyAccessToken, now: Date = Date()) async throws -> SeatUsageSnapshot {
        async let plan = getPlanInfo(access: access)
        async let period = getCurrentPeriodUsage(access: access)
        async let hardLimit = getHardLimit(access: access)
        async let credits = getCreditGrantsBalance(access: access)
        async let policy = getUsageLimitPolicyStatus(access: access)
        return SeatUsageSnapshot(
            seatID: seatID,
            plan: try await plan,
            period: try await period,
            hardLimit: try await hardLimit,
            credits: try await credits,
            policy: try await policy,
            fetchedAt: now
        )
    }

    public static func parsePeriodUsage(_ data: Data) throws -> PeriodUsageDetail {
        do {
            let dto = try JSONDecoder().decode(GetCurrentPeriodUsageWireDTO.self, from: data)
            return try DashboardPeriodWire.detail(from: dto)
        } catch let error as DashboardWireCodec.DecodeError {
            throw error
        } catch {
            throw ClientError.decode
        }
    }

    private func post(method: String, access: ConnectReadyAccessToken, body: Data = DashboardConnectTransport.personalEmptyBody) async throws -> Data {
        do {
            return try await transport.post(method: method, access: access, body: body)
        } catch let error as DashboardConnectTransport.TransportError {
            throw ClientError.transport(error)
        }
    }
}

extension DashboardClient.ClientError: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .transport(let error):
            error.description
        case .decode:
            "Dashboard response could not be decoded"
        case .invalidHardLimit:
            "Dashboard hard-limit state is invalid"
        }
    }

    public var debugDescription: String { description }

    public var surfaceMessage: String { description }
}
