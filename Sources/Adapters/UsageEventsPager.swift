import CursorBarDomain
import Foundation

/// Bounded newest-first pager for GetFilteredUsageEvents. Serial pages within one seat.
public struct UsageEventsPager: Sendable {
    public struct PagePolicy: Sendable, Equatable {
        public let pageSize: Int32
        public let maxEvents: Int

        public init(pageSize: Int32 = DashboardClient.filteredUsageEventsPageSize, maxEvents: Int = 10_000) {
            precondition(pageSize > 0)
            precondition(maxEvents > 0)
            self.pageSize = pageSize
            self.maxEvents = maxEvents
        }

        public static let standard = PagePolicy()
    }

    public struct Result: Sendable, Equatable {
        public let requests: [ActivityRequest]
        public let reportedTotal: Int
        public let truncated: Bool
        public let pagesFetched: Int

        public init(requests: [ActivityRequest], reportedTotal: Int, truncated: Bool, pagesFetched: Int) {
            self.requests = requests
            self.reportedTotal = reportedTotal
            self.truncated = truncated
            self.pagesFetched = pagesFetched
        }
    }

    public typealias PageFetch = @Sendable (_ page: Int32, _ pageSize: Int32) async throws -> (
        requests: [ActivityRequest],
        totalCount: Int
    )

    private let policy: PagePolicy

    public init(policy: PagePolicy = .standard) {
        self.policy = policy
    }

    public func fetchAll(fetchPage: PageFetch) async throws -> Result {
        var collected: [ActivityRequest] = []
        var reportedTotal = 0
        var page: Int32 = 1
        var pagesFetched = 0
        var truncated = false

        while true {
            let batch = try await fetchPage(page, policy.pageSize)
            pagesFetched += 1
            if page == 1 {
                reportedTotal = batch.totalCount
            }
            // API returns newest-first; keep that order while collecting, sort ascending at end.
            collected.append(contentsOf: batch.requests)

            let hitCap = collected.count >= policy.maxEvents
            let reachedTotal = reportedTotal > 0 && collected.count >= reportedTotal
            let shortPage = batch.requests.count < Int(policy.pageSize)
            if hitCap {
                if collected.count > policy.maxEvents {
                    collected = Array(collected.prefix(policy.maxEvents))
                }
                truncated = collected.count < reportedTotal || (reportedTotal == 0 && !shortPage)
                break
            }
            if reachedTotal || shortPage || batch.requests.isEmpty {
                truncated = reportedTotal > 0 && collected.count < reportedTotal
                break
            }
            page += 1
        }

        let ascending = collected.sorted { $0.timestampMs < $1.timestampMs }
        return Result(
            requests: ascending,
            reportedTotal: reportedTotal,
            truncated: truncated,
            pagesFetched: pagesFetched
        )
    }
}
