import Foundation

/// One connected account for CLI list / renewals. Credential-free.
public struct AgentAccountRow: Sendable, Equatable, Codable {
    public let seatID: String
    public let label: String
    public let userLabel: String?
    public let identity: String
    public let email: String?
    public let plan: String?
    public let renewal: Date?
    public let isActive: Bool
    public let cursorPercent: Int?
    public let apiPercent: Int?

    public init(
        seatID: String,
        label: String,
        userLabel: String?,
        identity: String,
        email: String? = nil,
        plan: String?,
        renewal: Date?,
        isActive: Bool,
        cursorPercent: Int?,
        apiPercent: Int?
    ) {
        self.seatID = seatID
        self.label = label
        self.userLabel = userLabel
        self.identity = identity
        self.email = email
        self.plan = plan
        self.renewal = renewal
        self.isActive = isActive
        self.cursorPercent = cursorPercent
        self.apiPercent = apiPercent
    }

    public init(seat: SeatPresentation, email: Email? = nil) {
        self.seatID = seat.seatID.rawValue
        self.label = seat.dashboardTitle
        self.userLabel = seat.userLabel?.value
        self.identity = seat.label.text
        self.email = (email ?? seat.revealedEmail)?.value
        self.plan = seat.planBadgeTitle
        self.renewal = seat.resetDate
        self.isActive = seat.isDesktopBound
        self.cursorPercent = seat.autoPercent.map { Int($0.percent.rounded()) }
        self.apiPercent = seat.apiPercent.map { Int($0.percent.rounded()) }
    }
}

public enum AgentAccountList {
    public static func rows(
        from seats: [SeatPresentation],
        emails: [SeatID: Email] = [:]
    ) -> [AgentAccountRow] {
        seats.filter(AddAccountPresentation.isConnectedAccount).map { seat in
            AgentAccountRow(seat: seat, email: emails[seat.seatID] ?? seat.revealedEmail)
        }
    }

    public static func upcomingRenewals(from rows: [AgentAccountRow], now: Date = Date()) -> [AgentAccountRow] {
        rows
            .filter { row in
                guard let renewal = row.renewal else { return false }
                return renewal >= now
            }
            .sorted { lhs, rhs in
                switch (lhs.renewal, rhs.renewal) {
                case let (l?, r?):
                    return l < r
                default:
                    return lhs.seatID < rhs.seatID
                }
            }
    }

    public static func textTable(_ rows: [AgentAccountRow], now: Date = Date()) -> String {
        guard !rows.isEmpty else { return "No connected accounts" }
        var lines = ["LABEL\tEMAIL\tIDENTITY\tPLAN\tRENEWAL\tACTIVE\tCURSOR\tAPI"]
        for row in rows {
            let renewal = row.renewal.map { formatRenewal($0, now: now) } ?? "—"
            lines.append(
                [
                    row.label,
                    row.email ?? "—",
                    row.identity,
                    row.plan ?? "—",
                    renewal,
                    row.isActive ? "yes" : "no",
                    row.cursorPercent.map { "\($0)%" } ?? "—",
                    row.apiPercent.map { "\($0)%" } ?? "—",
                ].joined(separator: "\t")
            )
        }
        return lines.joined(separator: "\n")
    }

    public static func json(_ rows: [AgentAccountRow]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(rows)
        return String(decoding: data, as: UTF8.self)
    }

    public static func formatRenewal(_ date: Date, now: Date = Date()) -> String {
        let days = Calendar.current.dateComponents([.day], from: startOfDay(now), to: startOfDay(date)).day ?? 0
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone.current
        let stamp = formatter.string(from: date)
        if days == 0 { return "\(stamp) (today)" }
        if days == 1 { return "\(stamp) (tomorrow)" }
        if days > 1 { return "\(stamp) (\(days)d)" }
        return stamp
    }

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}
