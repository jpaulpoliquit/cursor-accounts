import CursorBarDomain
import Foundation

/// Parallel GetMe createdAt lookups with bounded concurrency. One seat failure does not erase others.
public enum AllTimeBoundLookup {
    public static func resolve(
        credentials: [SeatUsageRefresher.SeatCredential],
        bindingEpochs: [SeatID: UInt64] = [:],
        client: DashboardClient = DashboardClient(),
        today: UsageDayKey = UsageDayKey.utcDay(containing: Date()),
        maxConcurrent: Int = AllTimeHistoryBoundsResolver.maxConcurrentLookups
    ) async -> AllTimeHistoryBounds? {
        guard !credentials.isEmpty else { return nil }
        let gate = FetchConcurrencyGate(limit: maxConcurrent)
        let seats = credentials.map(\.seatID)

        let results: [(SeatID, Date?, Bool)] = await withTaskGroup(
            of: (SeatID, Date?, Bool).self
        ) { group in
            for credential in credentials {
                group.addTask {
                    await gate.withPermit(seatID: credential.seatID) {
                        do {
                            let profile = try await client.getMeProfile(access: credential.access)
                            return (credential.seatID, profile.createdAt, false)
                        } catch {
                            return (credential.seatID, nil, true)
                        }
                    }
                }
            }
            var collected: [(SeatID, Date?, Bool)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        var createdAtBySeat: [SeatID: Date?] = [:]
        var failed: Set<SeatID> = []
        for (seatID, createdAt, didFail) in results {
            if didFail {
                failed.insert(seatID)
            } else {
                createdAtBySeat[seatID] = createdAt
            }
        }
        return AllTimeHistoryBoundsResolver.merge(
            seats: seats,
            createdAtBySeat: createdAtBySeat,
            failedSeats: failed,
            today: today
        )
    }
}
