import Foundation

/// One calendar month of implied Cursor pricing for a single model.
public struct ModelPricingMonth: Sendable, Equatable, Hashable, Codable {
    public let month: YearMonth
    public let requestCount: Int
    public let tokens: Int64
    public let usageValueCents: Int64
    public let onDemandChargedCents: Int64

    public init(
        month: YearMonth,
        requestCount: Int,
        tokens: Int64,
        usageValueCents: Int64,
        onDemandChargedCents: Int64
    ) {
        self.month = month
        self.requestCount = requestCount
        self.tokens = tokens
        self.usageValueCents = usageValueCents
        self.onDemandChargedCents = onDemandChargedCents
    }

    public var impliedCentsPerMillion: Int64? {
        ActivityModelCatalog.impliedCentsPerMillion(usageValueCents: usageValueCents, tokens: tokens)
    }
}

/// One model across the selected Insights range. Every distinct slug from history is kept.
public struct ModelPricingRow: Sendable, Equatable, Hashable, Codable {
    public let modelIntent: String
    public let displayName: String
    public let requestCount: Int
    public let tokens: Int64
    public let usageValueCents: Int64
    public let onDemandChargedCents: Int64
    public let usageValueEventCount: Int
    public let onDemandEventCount: Int
    public let months: [ModelPricingMonth]

    public init(
        modelIntent: String,
        displayName: String,
        requestCount: Int,
        tokens: Int64,
        usageValueCents: Int64,
        onDemandChargedCents: Int64,
        usageValueEventCount: Int,
        onDemandEventCount: Int,
        months: [ModelPricingMonth]
    ) {
        self.modelIntent = modelIntent
        self.displayName = displayName
        self.requestCount = requestCount
        self.tokens = tokens
        self.usageValueCents = usageValueCents
        self.onDemandChargedCents = onDemandChargedCents
        self.usageValueEventCount = usageValueEventCount
        self.onDemandEventCount = onDemandEventCount
        self.months = months
    }

    public var impliedCentsPerMillion: Int64? {
        ActivityModelCatalog.impliedCentsPerMillion(usageValueCents: usageValueCents, tokens: tokens)
    }

    /// Usage value Cursor did not collect as on-demand. Included-plan requests show up here.
    public var subsidizedCents: Int64 {
        max(0, usageValueCents - onDemandChargedCents)
    }

    public var firstPricedMonth: ModelPricingMonth? {
        months.first(where: { $0.impliedCentsPerMillion != nil })
    }

    public var lastPricedMonth: ModelPricingMonth? {
        months.last(where: { $0.impliedCentsPerMillion != nil })
    }

    public var pricedMonthCount: Int {
        months.filter { $0.impliedCentsPerMillion != nil }.count
    }
}

/// Models that share a `ModelDisplayNames.Family`, in family declaration order.
public struct ModelFamilySection: Sendable, Equatable, Identifiable {
    public var id: ModelDisplayNames.Family { family }
    public let family: ModelDisplayNames.Family
    public let rows: [ModelPricingRow]

    public init(family: ModelDisplayNames.Family, rows: [ModelPricingRow]) {
        self.family = family
        self.rows = rows
    }

    /// True when this family actually splits by generation (Grok 4.6 vs 4.5).
    public var showsLineHeaders: Bool {
        ActivityModelCatalog.familyTree(rows)
            .first { $0.family == family }?
            .showsLineHeaders ?? false
    }
}

/// One generation inside a family (`Cursor Grok 4.6`, `Sonnet 4.6`).
public struct ModelLineSection: Sendable, Equatable, Identifiable {
    public var id: String { line.id }
    public let line: ModelDisplayNames.Line
    public let rows: [ModelPricingRow]

    public init(line: ModelDisplayNames.Line, rows: [ModelPricingRow]) {
        self.line = line
        self.rows = rows
    }
}

/// All models in the fetched event slice, with implied Cursor rates and subsidy.
public struct ModelPricingCatalog: Sendable, Equatable, Hashable, Codable {
    public let models: [ModelPricingRow]
    public let totalUsageValueCents: Int64
    public let totalOnDemandChargedCents: Int64
    public let totalSubsidizedCents: Int64

    public init(
        models: [ModelPricingRow],
        totalUsageValueCents: Int64,
        totalOnDemandChargedCents: Int64,
        totalSubsidizedCents: Int64
    ) {
        self.models = models
        self.totalUsageValueCents = totalUsageValueCents
        self.totalOnDemandChargedCents = totalOnDemandChargedCents
        self.totalSubsidizedCents = totalSubsidizedCents
    }

    public static let empty = ModelPricingCatalog(
        models: [],
        totalUsageValueCents: 0,
        totalOnDemandChargedCents: 0,
        totalSubsidizedCents: 0
    )

    public var isEmpty: Bool { models.isEmpty }

    public static let methodologyCopy =
        "Implied price is Cursor usage value divided by tokens, blended across input, output, and cache. Not a vendor list price. Subsidized is usage value minus on-demand charged in this range."

    public static let impliedRateHelp =
        "Cursor usage value per million tokens in this range. Input, output, and cache tokens are mixed."

    public static let subsidizedHelp =
        "Usage value minus on-demand charged. Included-plan requests count as subsidized. This is not Cursor's unpublished vendor cost."
}

/// Pure catalog from typed usage events. No I/O.
public enum ActivityModelCatalog {
    public static func build(requests: [ActivityRequest], timeZone: TimeZone) -> ModelPricingCatalog {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var rows: [String: Acc] = [:]
        for request in requests {
            let date = Date(timeIntervalSince1970: TimeInterval(request.timestampMs) / 1000.0)
            let month = YearMonth(
                year: calendar.component(.year, from: date),
                month: calendar.component(.month, from: date)
            )
            var acc = rows[request.model] ?? Acc(modelIntent: request.model)
            acc.add(request, month: month)
            rows[request.model] = acc
        }
        let models = rows.values
            .map(\.row)
            .sorted { lhs, rhs in
                if lhs.usageValueCents != rhs.usageValueCents {
                    return lhs.usageValueCents > rhs.usageValueCents
                }
                if lhs.tokens != rhs.tokens {
                    return lhs.tokens > rhs.tokens
                }
                return lhs.modelIntent < rhs.modelIntent
            }
        let usage = models.reduce(Int64(0)) { $0 + $1.usageValueCents }
        let charged = models.reduce(Int64(0)) { $0 + $1.onDemandChargedCents }
        return ModelPricingCatalog(
            models: models,
            totalUsageValueCents: usage,
            totalOnDemandChargedCents: charged,
            totalSubsidizedCents: max(0, usage - charged)
        )
    }

    public static func familyTree(_ rows: [ModelPricingRow]) -> [ModelFamilyGroup<ModelPricingRow>] {
        ModelHierarchy.grouped(rows, intent: \.modelIntent, displayName: \.displayName)
    }

    /// Groups rows by the shared Newton tree. Empty families are omitted.
    public static func sectionsByFamily(_ rows: [ModelPricingRow]) -> [ModelFamilySection] {
        familyTree(rows).map { group in
            ModelFamilySection(family: group.family, rows: group.items)
        }
    }

    /// Generation buckets for one family, newest first. Row order is the input order.
    public static func lines(
        in rows: [ModelPricingRow],
        family: ModelDisplayNames.Family
    ) -> [ModelLineSection] {
        guard let group = familyTree(rows).first(where: { $0.family == family }) else {
            return []
        }
        return group.lines.map { ModelLineSection(line: $0.line, rows: $0.items) }
    }

    public static func impliedCentsPerMillion(usageValueCents: Int64, tokens: Int64) -> Int64? {
        guard usageValueCents > 0, tokens > 0 else { return nil }
        let (product, overflow) = usageValueCents.multipliedReportingOverflow(by: 1_000_000)
        guard !overflow else { return nil }
        return product / tokens
    }

    public static func formatRate(_ centsPerMillion: Int64) -> String {
        "\(ActivityCostSemantics.formatCents(centsPerMillion)) / 1M"
    }

    public static func rateChange(for row: ModelPricingRow, timeZone: TimeZone) -> ModelRateChange? {
        let priced = row.months.compactMap { month -> (YearMonth, Int64)? in
            guard let rate = month.impliedCentsPerMillion else { return nil }
            return (month.month, rate)
        }
        guard priced.count >= 2, let first = priced.first, let last = priced.last else {
            return nil
        }
        return ModelRateChange(
            startCentsPerMillion: first.1,
            endCentsPerMillion: last.1,
            monthRangeLabel: compactMonthRange(first.0, last.0, timeZone: timeZone),
            startMonthLabel: shortMonth(first.0, timeZone: timeZone),
            endMonthLabel: shortMonth(last.0, timeZone: timeZone)
        )
    }

    public static func rateTimelineCaption(for row: ModelPricingRow, timeZone: TimeZone) -> String? {
        rateChange(for: row, timeZone: timeZone)?.accessibilityLabel
    }

    public static func compactMonthRange(
        _ start: YearMonth,
        _ end: YearMonth,
        timeZone: TimeZone
    ) -> String {
        let startName = monthName(start, timeZone: timeZone)
        let endName = monthName(end, timeZone: timeZone)
        if start.year == end.year {
            return "\(startName)–\(endName)"
        }
        return "\(shortMonth(start, timeZone: timeZone))–\(shortMonth(end, timeZone: timeZone))"
    }

    public static func shortMonth(_ month: YearMonth, timeZone: TimeZone) -> String {
        formattedMonth(month, timeZone: timeZone, template: "MMM yyyy")
    }

    public static func monthName(_ month: YearMonth, timeZone: TimeZone) -> String {
        formattedMonth(month, timeZone: timeZone, template: "MMM")
    }

    private static func formattedMonth(
        _ month: YearMonth,
        timeZone: TimeZone,
        template: String
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = month.year
        components.month = month.month
        components.day = 1
        let date = calendar.date(from: components)!
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private struct Acc {
        var modelIntent: String
        var requestCount = 0
        var tokens: Int64 = 0
        var usageValueCents: Int64 = 0
        var onDemandChargedCents: Int64 = 0
        var usageValueEventCount = 0
        var onDemandEventCount = 0
        var months: [YearMonth: MonthAcc] = [:]

        mutating func add(_ request: ActivityRequest, month: YearMonth) {
            requestCount += 1
            tokens += request.tokens?.total ?? 0
            if let cents = request.usageValueCents {
                usageValueCents += cents
                usageValueEventCount += 1
            }
            if let cents = request.onDemandChargedCents {
                onDemandChargedCents += cents
                onDemandEventCount += 1
            }
            var monthAcc = months[month] ?? MonthAcc()
            monthAcc.add(request)
            months[month] = monthAcc
        }

        var row: ModelPricingRow {
            ModelPricingRow(
                modelIntent: modelIntent,
                displayName: ModelDisplayNames.displayName(for: modelIntent),
                requestCount: requestCount,
                tokens: tokens,
                usageValueCents: usageValueCents,
                onDemandChargedCents: onDemandChargedCents,
                usageValueEventCount: usageValueEventCount,
                onDemandEventCount: onDemandEventCount,
                months: months.keys.sorted().map { key in
                    let month = months[key]!
                    return ModelPricingMonth(
                        month: key,
                        requestCount: month.requestCount,
                        tokens: month.tokens,
                        usageValueCents: month.usageValueCents,
                        onDemandChargedCents: month.onDemandChargedCents
                    )
                }
            )
        }
    }

    private struct MonthAcc {
        var requestCount = 0
        var tokens: Int64 = 0
        var usageValueCents: Int64 = 0
        var onDemandChargedCents: Int64 = 0

        mutating func add(_ request: ActivityRequest) {
            requestCount += 1
            tokens += request.tokens?.total ?? 0
            usageValueCents += request.usageValueCents ?? 0
            onDemandChargedCents += request.onDemandChargedCents ?? 0
        }
    }
}
