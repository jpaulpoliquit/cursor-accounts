import Foundation

/// One account’s contribution on an inspected day. Share matches the active chart metric.
public struct UsageDayContributionRow: Sendable, Equatable, Hashable {
    public let seatID: SeatID
    public let label: String
    public let tokens: Int64
    public let spendCents: Int32?
    public let share: Double
    /// Honest cost-mode signal when this seat lacks spend for the day.
    public let costUnavailable: Bool

    public init(
        seatID: SeatID,
        label: String,
        tokens: Int64,
        spendCents: Int32?,
        share: Double,
        costUnavailable: Bool = false
    ) {
        self.seatID = seatID
        self.label = label
        self.tokens = tokens
        self.spendCents = spendCents
        self.share = share
        self.costUnavailable = costUnavailable
    }
}

/// Hover / VoiceOver inspection payload for one plotted day.
public struct UsageDayInspection: Sendable, Equatable, Hashable {
    public let day: UsageDayKey
    public let totalTokens: Int64
    public let spendCents: Int32?
    public let coverage: PointCoverage
    public let contributions: [UsageDayContributionRow]
    /// Cost mode with missing/partial per-account spend for the plotted stack.
    public let costCompositionUnavailable: Bool

    public init(
        day: UsageDayKey,
        totalTokens: Int64,
        spendCents: Int32?,
        coverage: PointCoverage,
        contributions: [UsageDayContributionRow],
        costCompositionUnavailable: Bool = false
    ) {
        self.day = day
        self.totalTokens = totalTokens
        self.spendCents = spendCents
        self.coverage = coverage
        self.contributions = contributions
        self.costCompositionUnavailable = costCompositionUnavailable
    }

    public func accessibilityLabel(metric: UsageMetric, locale: Locale = .current) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(day.utcMidnightMs) / 1000.0)
        let dateText = date.formatted(
            .dateTime.year().month(.wide).day().locale(locale)
        )
        var parts = [dateText]
        switch metric {
        case .tokens:
            parts.append("total \(TokenCountFormat.accessibility(totalTokens, locale: locale)) tokens")
            if !contributions.isEmpty {
                let rows = contributions.map { row in
                    "\(row.label) \(TokenCountFormat.compact(row.tokens)) \(TokenCountFormat.percentShare(row.share))"
                }
                parts.append(contentsOf: rows)
            }
        case .costCents:
            if let spendCents {
                parts.append("total \(CostCountFormat.accessibilityCents(spendCents, locale: locale))")
            } else {
                parts.append("total cost unavailable")
            }
            if costCompositionUnavailable {
                parts.append("per-account cost unavailable")
            } else if !contributions.isEmpty {
                let rows = contributions.map { row -> String in
                    if row.costUnavailable {
                        return "\(row.label) cost unavailable"
                    }
                    let amount = CostCountFormat.accessibilityCents(row.spendCents ?? 0, locale: locale)
                    return "\(row.label) \(amount) \(TokenCountFormat.percentShare(row.share))"
                }
                parts.append(contentsOf: rows)
            }
        }
        if coverage != .complete {
            parts.append("coverage \(coverage.rawValue)")
        }
        return parts.joined(separator: ", ")
    }

    public func tooltipTotalText(metric: UsageMetric) -> String {
        switch metric {
        case .tokens:
            return "\(TokenCountFormat.compact(totalTokens)) tokens"
        case .costCents:
            if let spendCents {
                return CostCountFormat.accessibilityCents(spendCents)
            }
            return "Cost unavailable"
        }
    }

    /// Hover list: drop zero rows, and skip a single 100% row (the title already says the total).
    public func tooltipContributions(metric: UsageMetric) -> [UsageDayContributionRow] {
        let rows = contributions.filter { row in
            switch metric {
            case .tokens:
                return row.tokens > 0
            case .costCents:
                return row.costUnavailable || (row.spendCents ?? 0) > 0
            }
        }
        if rows.count <= 1 { return [] }
        return rows
    }

    public func tooltipRowText(_ row: UsageDayContributionRow, metric: UsageMetric) -> String {
        switch metric {
        case .tokens:
            return "\(TokenCountFormat.compact(row.tokens)) · \(TokenCountFormat.percentShare(row.share))"
        case .costCents:
            if row.costUnavailable || row.spendCents == nil {
                return "Unavailable"
            }
            return "\(CostCountFormat.accessibilityCents(row.spendCents!)) · \(TokenCountFormat.percentShare(row.share))"
        }
    }
}

/// Precomputed nearest-day index for pointer inspection. Pure in-memory; no network.
public struct UsageChartInspectionIndex: Sendable, Equatable {
    public let inspections: [UsageDayInspection]
    public let metric: UsageMetric
    private let midnights: [Int64]

    public init(
        points: [UsagePoint],
        accountLabels: [SeatID: String],
        includeContributions: Bool,
        metric: UsageMetric = .tokens
    ) {
        self.metric = metric
        var rows: [UsageDayInspection] = []
        var midnights: [Int64] = []
        for point in points where point.coverage != .missing {
            midnights.append(point.day.utcMidnightMs)
            let built = Self.buildInspection(
                point: point,
                labels: accountLabels,
                includeContributions: includeContributions,
                metric: metric
            )
            rows.append(built)
        }
        self.inspections = rows
        self.midnights = midnights
    }

    public var isEmpty: Bool { inspections.isEmpty }

    public func nearest(to date: Date) -> UsageDayInspection? {
        guard !midnights.isEmpty else { return nil }
        let target = Int64(date.timeIntervalSince1970 * 1000.0)
        var bestIndex = 0
        var bestDistance = abs(midnights[0] - target)
        for index in midnights.indices.dropFirst() {
            let distance = abs(midnights[index] - target)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return inspections[bestIndex]
    }

    public func inspection(for day: UsageDayKey) -> UsageDayInspection? {
        inspections.first(where: { $0.day == day })
    }

    private static func buildInspection(
        point: UsagePoint,
        labels: [SeatID: String],
        includeContributions: Bool,
        metric: UsageMetric
    ) -> UsageDayInspection {
        guard includeContributions else {
            return UsageDayInspection(
                day: point.day,
                totalTokens: point.tokens,
                spendCents: point.spendCents,
                coverage: point.coverage,
                contributions: [],
                costCompositionUnavailable: metric == .costCents && point.spendCents == nil
            )
        }
        switch metric {
        case .tokens:
            return UsageDayInspection(
                day: point.day,
                totalTokens: point.tokens,
                spendCents: point.spendCents,
                coverage: point.coverage,
                contributions: tokenRows(point: point, labels: labels),
                costCompositionUnavailable: false
            )
        case .costCents:
            return costInspection(point: point, labels: labels)
        }
    }

    private static func tokenRows(
        point: UsagePoint,
        labels: [SeatID: String]
    ) -> [UsageDayContributionRow] {
        let total = point.tokens
        let sorted = point.contributions.sorted { lhs, rhs in
            if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
            return lhs.seatID.rawValue < rhs.seatID.rawValue
        }
        return sorted.map { contribution in
            let share: Double
            if total > 0 {
                share = Double(contribution.tokens) / Double(total)
            } else {
                share = 0
            }
            return UsageDayContributionRow(
                seatID: contribution.seatID,
                label: labels[contribution.seatID] ?? "Account",
                tokens: contribution.tokens,
                spendCents: contribution.spendCents,
                share: share,
                costUnavailable: false
            )
        }
    }

    private static func costInspection(
        point: UsagePoint,
        labels: [SeatID: String]
    ) -> UsageDayInspection {
        let spendValues = point.contributions.compactMap(\.spendCents)
        let anyMissing = point.contributions.contains(where: { $0.spendCents == nil })
        // Plot stacks spendCents when present; inspection must match that stack, not tokens.
        guard point.spendCents != nil, !point.contributions.isEmpty, !anyMissing else {
            return UsageDayInspection(
                day: point.day,
                totalTokens: point.tokens,
                spendCents: point.spendCents,
                coverage: point.coverage,
                contributions: point.contributions.map { contribution in
                    UsageDayContributionRow(
                        seatID: contribution.seatID,
                        label: labels[contribution.seatID] ?? "Account",
                        tokens: contribution.tokens,
                        spendCents: contribution.spendCents,
                        share: 0,
                        costUnavailable: contribution.spendCents == nil
                    )
                },
                costCompositionUnavailable: true
            )
        }
        let total = Int64(spendValues.reduce(0) { $0 + Int64($1) })
        let sorted = point.contributions.sorted { lhs, rhs in
            let l = lhs.spendCents ?? 0
            let r = rhs.spendCents ?? 0
            if l != r { return l > r }
            return lhs.seatID.rawValue < rhs.seatID.rawValue
        }
        let rows = sorted.map { contribution -> UsageDayContributionRow in
            let cents = contribution.spendCents ?? 0
            let share: Double
            if total > 0 {
                share = Double(cents) / Double(total)
            } else {
                share = 0
            }
            return UsageDayContributionRow(
                seatID: contribution.seatID,
                label: labels[contribution.seatID] ?? "Account",
                tokens: contribution.tokens,
                spendCents: contribution.spendCents,
                share: share,
                costUnavailable: false
            )
        }
        return UsageDayInspection(
            day: point.day,
            totalTokens: point.tokens,
            spendCents: point.spendCents,
            coverage: point.coverage,
            contributions: rows,
            costCompositionUnavailable: false
        )
    }
}

/// Stable accent palette keyed by SeatID (not roster position order at render time).
public enum UsageAccountChartColor: Sendable, Equatable {
    public static let paletteCount = 5

    public static func index(for seatID: SeatID) -> Int {
        let n = seatID.displayIndex
        if n == Int.max { return 0 }
        return (n - 1) % paletteCount
    }
}
