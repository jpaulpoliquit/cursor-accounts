import CursorBarDomain
import Foundation

/// Parallel per-seat usage refresh with single-flight and last-known retention.
public actor SeatUsageRefresher {
    public struct SeatCredential: Sendable {
        public let seatID: SeatID
        public let access: ConnectReadyAccessToken

        public init(seatID: SeatID, access: ConnectReadyAccessToken) {
            self.seatID = seatID
            self.access = access
        }

        public init?(seatID: SeatID, access: AccessToken) {
            guard let ready = ConnectReadyAccessToken(access) else { return nil }
            self.seatID = seatID
            self.access = ready
        }
    }

    private let client: DashboardClient
    private let seatGate: FetchConcurrencyGate
    private var lastKnown: [SeatID: SeatUsageSnapshot] = [:]
    private var refreshGeneration: UInt64 = 0
    /// App-owned binding identity per seat; set via invalidateBinding before rebind.
    private var bindingEpochBySeat: [SeatID: UInt64] = [:]
    private var setInFlight: Set<SeatID> = []

    public init(
        client: DashboardClient = DashboardClient(),
        maxConcurrentSeats: Int = FetchConcurrencyGate.defaultLimit,
        gate: FetchConcurrencyGate? = nil
    ) {
        self.client = client
        self.seatGate = gate ?? FetchConcurrencyGate(limit: maxConcurrentSeats)
    }

    public func maxObservedSeatInFlight() async -> Int {
        await seatGate.maxObservedInFlight
    }

    public func lastKnownSnapshot(for seatID: SeatID) -> SeatUsageSnapshot? {
        lastKnown[seatID]
    }

    public func allLastKnown() -> [SeatID: SeatUsageSnapshot] {
        lastKnown
    }

    /// Invalidate card binding and last-known before the SeatID can be rebound.
    public func invalidateBinding(seatID: SeatID, epoch: UInt64) {
        refreshGeneration &+= 1
        bindingEpochBySeat[seatID] = epoch
        lastKnown[seatID] = nil
    }

    public func refreshAll(
        credentials: [SeatCredential],
        bindingEpochs: [SeatID: UInt64]
    ) async -> UsageRefreshCommit {
        refreshGeneration &+= 1
        let token = refreshGeneration
        let capturedEpochs = bindingEpochs
        let client = self.client
        let seatGate = self.seatGate
        let fetched = await withTaskGroup(
            of: (SeatID, SeatUsageRefreshOutcome, SeatUsageSnapshot?).self
        ) { group in
            for credential in credentials {
                group.addTask {
                    await seatGate.withPermit(seatID: credential.seatID) {
                        await Self.fetchOutcome(client: client, credential: credential)
                    }
                }
            }
            var collected: [(SeatID, SeatUsageRefreshOutcome, SeatUsageSnapshot?)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        guard token == refreshGeneration else { return .discarded }

        var outcomes: [SeatID: SeatUsageRefreshOutcome] = [:]
        for (seatID, outcome, snapshot) in fetched {
            guard Self.bindingStillCurrent(
                seatID: seatID,
                captured: capturedEpochs[seatID] ?? 0,
                current: bindingEpochBySeat[seatID] ?? 0
            ) else {
                continue
            }
            outcomes[seatID] = outcome
            if let snapshot {
                lastKnown[seatID] = snapshot
            }
        }
        guard !outcomes.isEmpty else { return .discarded }
        return .applied(UsageRefreshReport(outcomes: outcomes, bindingEpochs: capturedEpochs))
    }

    public func refresh(
        credential: SeatCredential,
        bindingEpoch: UInt64
    ) async -> UsageRefreshCommit {
        refreshGeneration &+= 1
        let token = refreshGeneration
        let capturedEpoch = bindingEpoch
        let client = self.client
        let (seatID, outcome, snapshot) = await Self.fetchOutcome(client: client, credential: credential)
        guard token == refreshGeneration else { return .discarded }
        guard Self.bindingStillCurrent(
            seatID: seatID,
            captured: capturedEpoch,
            current: bindingEpochBySeat[seatID] ?? 0
        ) else {
            return .discarded
        }
        if let snapshot {
            lastKnown[seatID] = snapshot
        }
        return .applied(
            UsageRefreshReport(
                outcomes: [seatID: outcome],
                bindingEpochs: [seatID: capturedEpoch]
            )
        )
    }

    private static func bindingStillCurrent(
        seatID: SeatID,
        captured: UInt64,
        current: UInt64
    ) -> Bool {
        captured == current
    }

    /// Serializes SetHardLimit per seat, checks policy, then re-reads into one snapshot.
    public func setOnDemand(
        credential: SeatCredential,
        mode: OnDemandMode
    ) async -> Result<SetHardLimitSuccess, SetHardLimitFailure> {
        guard !setInFlight.contains(credential.seatID) else {
            return .failure(.alreadyWriting)
        }
        setInFlight.insert(credential.seatID)
        defer { setInFlight.remove(credential.seatID) }

        let policy: UsagePolicy
        do {
            policy = try await client.getUsageLimitPolicyStatus(access: credential.access)
        } catch {
            return .failure(.mapped(error))
        }
        guard policy.allowsOnDemandAdjust else {
            return .failure(.policyDenied)
        }

        do {
            try await client.setHardLimit(access: credential.access, mode: mode)
        } catch {
            return .failure(.mapped(error))
        }

        do {
            async let hardLimit = client.getHardLimit(access: credential.access)
            async let period = client.getCurrentPeriodUsage(access: credential.access)
            async let plan = client.getPlanInfo(access: credential.access)
            async let credits = client.getCreditGrantsBalance(access: credential.access)
            async let freshPolicy = client.getUsageLimitPolicyStatus(access: credential.access)
            let snapshot = SeatUsageSnapshot(
                seatID: credential.seatID,
                plan: try await plan,
                period: try await period,
                hardLimit: try await hardLimit,
                credits: try await credits,
                policy: try await freshPolicy,
                fetchedAt: Date()
            )
            lastKnown[credential.seatID] = snapshot
            return .success(.applied(snapshot))
        } catch {
            return .success(.writtenUnconfirmed(credential.seatID))
        }
    }

    private nonisolated static func fetchOutcome(
        client: DashboardClient,
        credential: SeatCredential
    ) async -> (SeatID, SeatUsageRefreshOutcome, SeatUsageSnapshot?) {
        do {
            let snapshot = try await client.fetchSeatUsage(
                seatID: credential.seatID,
                access: credential.access
            )
            return (credential.seatID, .refreshed(snapshot), snapshot)
        } catch is CancellationError {
            return (credential.seatID, .failed(message: "Usage refresh cancelled"), nil)
        } catch let error as DashboardClient.ClientError {
            return (credential.seatID, .failed(message: error.surfaceMessage), nil)
        } catch {
            return (credential.seatID, .failed(message: "Usage refresh failed"), nil)
        }
    }
}

public enum SetHardLimitFailure: Error, Sendable, Equatable {
    case alreadyWriting
    case policyDenied
    case transport(DashboardConnectTransport.TransportError)
    case decode
    case invalidHardLimit
    case unknown

    public var surfaceMessage: String {
        switch self {
        case .alreadyWriting:
            "SetHardLimit already in progress for this seat"
        case .policyDenied:
            "On-demand changes are not allowed for this account"
        case .transport(let error):
            error.description
        case .decode:
            "Dashboard response could not be decoded"
        case .invalidHardLimit:
            "Dashboard hard-limit state is invalid"
        case .unknown:
            "SetHardLimit failed"
        }
    }

    static func mapped(_ error: Error) -> SetHardLimitFailure {
        if let client = error as? DashboardClient.ClientError {
            switch client {
            case .transport(let transport):
                return .transport(transport)
            case .decode:
                return .decode
            case .invalidHardLimit:
                return .invalidHardLimit
            }
        }
        return .unknown
    }
}

extension SetHardLimitFailure: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { surfaceMessage }
    public var debugDescription: String { surfaceMessage }
}
