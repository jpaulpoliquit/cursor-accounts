import CursorBarAdapters
import CursorBarDomain
import Foundation

enum AgentCLIRuntime {
    static func run(_ args: [String]) async -> Int32 {
        switch AgentCLIParser.parse(args) {
        case .failure(let error):
            return fail(error.message)
        case .success(.help):
            FileHandle.standardOutput.write(Data((AgentCLIParser.helpText + "\n").utf8))
            return 0
        case .success(let request):
            return await execute(request)
        }
    }

    private static func execute(_ request: AgentCLIRequest) async -> Int32 {
        let labelStore = SeatUserLabelStore()
        let cards = UsageCardSnapshotStore().load()
        let chart = UsageChartSnapshotStore().load()

        switch request {
        case .help:
            FileHandle.standardOutput.write(Data((AgentCLIParser.helpText + "\n").utf8))
            return 0
        case .usage(let group, let seatQuery, let json):
            let loaded = loadAccounts(cards: cards, labels: labelStore, allowKeychain: seatQuery != nil)
            return printUsage(
                chart: chart,
                cards: cards,
                seats: loaded.seats,
                emails: loaded.emails,
                group: group,
                seatQuery: seatQuery,
                json: json
            )
        case .list(let json):
            let loaded = loadAccounts(cards: cards, labels: labelStore, allowKeychain: true)
            return printRows(AgentAccountList.rows(from: loaded.seats, emails: loaded.emails), json: json)
        case .renewals(let json):
            let loaded = loadAccounts(cards: cards, labels: labelStore, allowKeychain: true)
            return printRows(
                AgentAccountList.upcomingRenewals(from: AgentAccountList.rows(from: loaded.seats, emails: loaded.emails)),
                json: json
            )
        case .label(let target, let text):
            let loaded = loadAccounts(cards: cards, labels: labelStore, allowKeychain: true)
            return setLabel(target: target, text: text, seats: loaded.seats, emails: loaded.emails, store: labelStore)
        case .switchAccount(let target, let force):
            let loaded = loadAccounts(cards: cards, labels: labelStore, allowKeychain: true)
            return await switchAccount(target: target, force: force, seats: loaded.seats, emails: loaded.emails)
        }
    }

    private struct LoadedAccounts {
        var seats: [SeatPresentation]
        var emails: [SeatID: Email]
    }

    private static func emails(from snapshots: [SeatSnapshot]) -> [SeatID: Email] {
        var mapped: [SeatID: Email] = [:]
        for seat in snapshots {
            if let email = seat.email {
                mapped[seat.seatID] = email
            }
        }
        return mapped
    }

    private static func loadAccounts(
        cards: [SeatID: SeatUsageSnapshot],
        labels: SeatUserLabelStore,
        allowKeychain: Bool
    ) -> LoadedAccounts {
        if let roster = PublicRosterStore().load() {
            let emails = emails(from: roster.seats)
            var mapped = labels.labels(seatIDs: roster.seats.map(\.seatID), emails: emails)
            for (raw, text) in roster.userLabels {
                if let seatID = SeatID(rawValue: raw), let label = SeatUserLabel(text) {
                    mapped[seatID] = mapped[seatID] ?? label
                }
            }
            return LoadedAccounts(
                seats: project(
                    snapshots: roster.seats,
                    cards: cards,
                    userLabels: mapped,
                    bound: roster.desktopBoundSeatID.flatMap(SeatID.init(rawValue:))
                ).connectedAccounts,
                emails: emails
            )
        }
        guard allowKeychain else { return LoadedAccounts(seats: [], emails: [:]) }
        let records: [StoredSeatRecord]
        do {
            records = try SeatKeychainStore().loadAll()
        } catch {
            return LoadedAccounts(seats: [], emails: [:])
        }
        let snapshots = records.map { $0.publicSnapshot(usage: cards[$0.seatID]?.period.usage) }
        let userLabels = labels.labels(for: records)
        PublicRosterStore().write(
            aggregate: AggregateSnapshot(seats: snapshots),
            userLabels: userLabels,
            desktopBoundSeatID: nil
        )
        return LoadedAccounts(
            seats: project(
                snapshots: snapshots,
                cards: cards,
                userLabels: userLabels,
                bound: nil
            ).connectedAccounts,
            emails: emails(from: snapshots)
        )
    }

    private static func project(
        snapshots: [SeatSnapshot],
        cards: [SeatID: SeatUsageSnapshot],
        userLabels: [SeatID: SeatUserLabel],
        bound: SeatID?
    ) -> AppPresentation {
        let policy = IdentityDisplayPolicy(
            rawValue: UserDefaults.standard.string(forKey: IdentityDisplayPolicy.defaultsKey) ?? ""
        ) ?? .maskEmail
        let focus = snapshots.map(\.seatID).sorted().first ?? .seat1
        return SeatPresentationProjector.project(
            aggregate: AggregateSnapshot(seats: snapshots),
            usageBySeat: cards,
            identityPolicy: policy,
            focusedSeatID: focus,
            loginPhases: [:],
            bootstrapPhase: .settled(.kept(focus)),
            usageRefreshPhase: .idle,
            setHardLimitPhase: .idle,
            desktopBoundSeatID: bound,
            userLabels: userLabels
        )
    }

    private static func printRows(_ rows: [AgentAccountRow], json: Bool) -> Int32 {
        if json {
            do {
                print(try AgentAccountList.json(rows))
                return 0
            } catch {
                return fail("cannot encode JSON")
            }
        }
        print(AgentAccountList.textTable(rows))
        return 0
    }

    private static func setLabel(
        target: String,
        text: String?,
        seats: [SeatPresentation],
        emails: [SeatID: Email],
        store: SeatUserLabelStore
    ) -> Int32 {
        guard let seatID = AgentSeatTarget.resolve(query: target, seats: seats, emails: emails) else {
            return fail("no account matches \(target)")
        }
        let record = try? SeatKeychainStore().load(seatID: seatID)
        let email = record?.email ?? emails[seatID]
        if let text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                store.set(label: nil, identity: record?.identity, email: email, seatID: seatID)
                print("cleared label for \(email?.value ?? seatID.rawValue)")
                return 0
            }
            guard let label = SeatUserLabel(trimmed) else {
                return fail("invalid label")
            }
            store.set(label: label, identity: record?.identity, email: email, seatID: seatID)
            print("labeled \(email?.value ?? seatID.rawValue) as \(label.value)")
            return 0
        }
        let current = seats.first(where: { $0.seatID == seatID })
        print(current?.userLabel?.value ?? current?.dashboardTitle ?? seatID.rawValue)
        return 0
    }

    private static func printUsage(
        chart: UsageChartSnapshot?,
        cards: [SeatID: SeatUsageSnapshot],
        seats: [SeatPresentation],
        emails: [SeatID: Email],
        group: AgentUsageGroup?,
        seatQuery: String?,
        json: Bool
    ) -> Int32 {
        var seatID: SeatID?
        if let seatQuery {
            guard let resolved = AgentSeatTarget.resolve(query: seatQuery, seats: seats, emails: emails) else {
                return fail("no account matches \(seatQuery)")
            }
            seatID = resolved
        }
        let reports = AgentUsageReport.make(snapshot: chart, group: group, cards: cards, seatID: seatID)
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(reports),
                  let text = String(data: data, encoding: .utf8)
            else {
                return fail("cannot encode JSON")
            }
            print(text)
            return 0
        }
        for report in reports {
            if reports.count > 1 {
                print("[\(report.group.rawValue)]")
            }
            print(report.text)
        }
        return reports.contains(where: \.available) ? 0 : 1
    }

    private static func switchAccount(
        target: String,
        force: Bool,
        seats: [SeatPresentation],
        emails: [SeatID: Email]
    ) async -> Int32 {
        guard let seatID = AgentSeatTarget.resolve(query: target, seats: seats, emails: emails) else {
            return fail("no account matches \(target)")
        }
        let keychain = SeatKeychainStore()
        let auth = AuthEngine(store: keychain)
        let engine = IDESwitchEngine(auth: auth, credentialStore: keychain)
        switch await engine.beginRequest(seatID: seatID) {
        case .failure(let reason):
            return fail(reason.menuMessage)
        case .success:
            break
        }
        var phase = await engine.runConfirmed(.confirmed(seatID: seatID))
        if phase.forceQuitPrompt != nil {
            guard force else {
                return fail("Cursor is still running. Re-run with --force to force-quit and continue.")
            }
            phase = await engine.forceQuitAfterTimeout()
        }
        if let status = phase.menuStatusText {
            print(status)
        } else {
            print("switched to \(target)")
        }
        if case .failed = phase { return 1 }
        PublicRosterStore().markDesktopBound(seatID)
        return 0
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data(("error: \(message)\n").utf8))
        return 1
    }
}
