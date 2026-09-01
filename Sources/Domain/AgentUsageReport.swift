import Foundation

/// Cached usage groups for the CLI. Prints last-known dashboard data; does not fetch.
public struct AgentUsageReport: Sendable, Equatable, Codable {
    public let group: AgentUsageGroup
    public let lines: [String]
    public let available: Bool

    public init(group: AgentUsageGroup, lines: [String], available: Bool) {
        self.group = group
        self.lines = lines
        self.available = available
    }

    public var text: String {
        if lines.isEmpty {
            return available ? "No usage in this group" : "No cached usage. Open the dashboard once, then retry."
        }
        return lines.joined(separator: "\n")
    }

    public static func make(
        snapshot: UsageChartSnapshot?,
        group: AgentUsageGroup?,
        cards: [SeatID: SeatUsageSnapshot] = [:],
        seatID: SeatID? = nil
    ) -> [AgentUsageReport] {
        let groups = group.map { [$0] } ?? AgentUsageGroup.allCases
        return groups.map { make(snapshot: snapshot, group: $0, cards: cards, seatID: seatID) }
    }

    public static func make(
        snapshot: UsageChartSnapshot?,
        group: AgentUsageGroup,
        cards: [SeatID: SeatUsageSnapshot] = [:],
        seatID: SeatID? = nil
    ) -> AgentUsageReport {
        switch group {
        case .tokens:
            return tokens(snapshot: snapshot, cards: cards, seatID: seatID)
        case .family:
            return family(snapshot: snapshot)
        case .activity:
            return activity(snapshot: snapshot)
        case .time:
            return time(snapshot: snapshot)
        case .models:
            return models(snapshot: snapshot)
        }
    }

    private static func tokens(
        snapshot: UsageChartSnapshot?,
        cards: [SeatID: SeatUsageSnapshot],
        seatID: SeatID?
    ) -> AgentUsageReport {
        if let summary = snapshot?.tokenSummary {
            let t = summary.totals
            let lines = CLITextTable.pairRows([
                ("input", TokenCountFormat.compact(t.input)),
                ("output", TokenCountFormat.compact(t.output)),
                ("cacheWrite", TokenCountFormat.compact(t.cacheWrite)),
                ("cacheRead", TokenCountFormat.compact(t.cacheRead)),
                ("total", TokenCountFormat.compact(t.total)),
            ])
            return AgentUsageReport(group: .tokens, lines: lines, available: true)
        }
        if let seatID, let card = cards[seatID] {
            let usage = card.period.usage
            let lines = CLITextTable.pairRows([
                ("cursor", "\(Int(usage.autoPercentUsed.percent.rounded()))%"),
                ("api", "\(Int(usage.apiPercentUsed.percent.rounded()))%"),
                ("total", "\(Int(usage.totalPercentUsed.percent.rounded()))%"),
            ])
            return AgentUsageReport(group: .tokens, lines: lines, available: true)
        }
        if seatID == nil, !cards.isEmpty {
            let body = cards.keys.sorted().compactMap { id -> [String]? in
                guard let card = cards[id] else { return nil }
                let usage = card.period.usage
                return [
                    id.rawValue,
                    "\(Int(usage.autoPercentUsed.percent.rounded()))%",
                    "\(Int(usage.apiPercentUsed.percent.rounded()))%",
                ]
            }
            let lines = CLITextTable.alignedRows(
                headers: ["Account", "Cursor", "API"],
                rows: body
            )
            return AgentUsageReport(group: .tokens, lines: lines, available: true)
        }
        return AgentUsageReport(group: .tokens, lines: [], available: false)
    }

    private static func family(snapshot: UsageChartSnapshot?) -> AgentUsageReport {
        guard let summary = snapshot?.tokenSummary else {
            return AgentUsageReport(group: .family, lines: [], available: false)
        }
        let families = ModelHierarchy.grouped(
            summary.topModels.map(\.model),
            intent: \.modelIntent,
            displayName: \.displayName
        )
        let lines = CLITextTable.pairRows(families.map { family in
            let tokens = family.items.reduce(Int64(0)) { $0 + $1.buckets.total }
            return (family.family.title, TokenCountFormat.compact(tokens))
        })
        return AgentUsageReport(group: .family, lines: lines, available: true)
    }

    private static func activity(snapshot: UsageChartSnapshot?) -> AgentUsageReport {
        guard let insights = snapshot?.insights else {
            return AgentUsageReport(group: .activity, lines: [], available: false)
        }
        var lines = CLITextTable.pairRows([
            ("requests", TokenCountFormat.grouped(insights.totalRequests)),
            ("tokens", TokenCountFormat.compact(insights.totalTokens)),
            ("activeDays", TokenCountFormat.grouped(insights.activeDayCount)),
        ])
        lines.append(insights.peakHourRangeAccessibility)
        return AgentUsageReport(group: .activity, lines: lines, available: true)
    }

    private static func time(snapshot: UsageChartSnapshot?) -> AgentUsageReport {
        guard let insights = snapshot?.insights else {
            return AgentUsageReport(group: .time, lines: [], available: false)
        }
        var pairs: [(String, String)] = []
        if let active = insights.medianEstimatedActiveMs {
            pairs.append(("medianAgent", formatDuration(active)))
        }
        if let span = insights.medianDailySpanMs {
            pairs.append(("medianSpan", formatDuration(span)))
        }
        var lines = [insights.agentTimeLabel]
        lines.append(contentsOf: CLITextTable.pairRows(pairs))
        return AgentUsageReport(group: .time, lines: lines, available: true)
    }

    private static func models(snapshot: UsageChartSnapshot?) -> AgentUsageReport {
        guard let summary = snapshot?.tokenSummary else {
            return AgentUsageReport(group: .models, lines: [], available: false)
        }
        let lines = CLITextTable.alignedRows(
            headers: ["Model", "Tokens", "Share"],
            rows: summary.topLines.map { line in
                let share = Int((line.share * 100).rounded())
                return [line.title, TokenCountFormat.compact(line.tokens), "\(share)%"]
            }
        )
        return AgentUsageReport(group: .models, lines: lines, available: true)
    }

    private static func formatDuration(_ ms: Int64) -> String {
        let minutes = max(0, ms / 60_000)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours)h" : "\(hours)h \(rem)m"
    }
}
