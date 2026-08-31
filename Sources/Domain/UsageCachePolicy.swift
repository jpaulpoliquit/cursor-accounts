import Foundation

/// Why usage work is being requested. Login and manual always hit the network.
public enum UsageFetchTrigger: Sendable, Equatable {
    case signedIn
    case manual
    case surfaceOpen
    case bootstrap
}

/// TTL gate for card/series refetch. Disk last-known can paint before this runs.
public enum UsageCachePolicy {
    public static let ttl: TimeInterval = 5 * 60

    public static func needsNetworkFetch(
        trigger: UsageFetchTrigger,
        fetchedAt: Date?,
        now: Date = Date(),
        ttl: TimeInterval = ttl
    ) -> Bool {
        switch trigger {
        case .signedIn, .manual:
            return true
        case .surfaceOpen, .bootstrap:
            guard let fetchedAt else { return true }
            return now.timeIntervalSince(fetchedAt) >= ttl
        }
    }

    public static func credentialsNeedingFetch<Credential>(
        _ credentials: [Credential],
        seatID: (Credential) -> SeatID,
        trigger: UsageFetchTrigger,
        fetchedAt: (SeatID) -> Date?,
        now: Date = Date(),
        ttl: TimeInterval = ttl
    ) -> [Credential] {
        credentials.filter { credential in
            needsNetworkFetch(
                trigger: trigger,
                fetchedAt: fetchedAt(seatID(credential)),
                now: now,
                ttl: ttl
            )
        }
    }
}
