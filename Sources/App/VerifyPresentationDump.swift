import CursorBarAdapters
import CursorBarDomain
import Foundation

/// Verify-only privacy-safe presentation dump for acceptance when AX/TCC is unavailable.
@MainActor
enum VerifyPresentationDump {
    static func dumpIfRequested(model: AppModel) {
        guard let path = outputPath() else { return }
        if CommandLine.arguments.contains("--mask-email") {
            model.identityPolicy = .maskEmail
        }
        let body = render(model: model)
        let url = URL(fileURLWithPath: path)
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            let marker = URL(fileURLWithPath: "/tmp/cursorbar-presentation-dumped")
            try "ok".write(to: marker, atomically: true, encoding: .utf8)
        } catch {
            let err = URL(fileURLWithPath: "/tmp/cursorbar-presentation-dump-error")
            try? "write_failed".write(to: err, atomically: true, encoding: .utf8)
        }
    }

    static func scheduleIfRequested(model: AppModel) {
        guard outputPath() != nil else { return }
        dumpIfRequested(model: model)
        for delay in [2.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                dumpIfRequested(model: model)
            }
        }
    }

    private static func outputPath() -> String? {
        for arg in CommandLine.arguments {
            if arg == "--dump-presentation" {
                return "/tmp/cursorbar-presentation-dump.txt"
            }
            if arg.hasPrefix("--dump-presentation=") {
                let path = String(arg.dropFirst("--dump-presentation=".count))
                return path.isEmpty ? nil : path
            }
        }
        return nil
    }

    private static func render(model: AppModel) -> String {
        let presentation = model.presentation
        let usage = model.usageSeries
        var lines: [String] = []
        lines.append("VERIFY_PRESENTATION")
        lines.append("dashboard_visible=\(model.dashboardVisible)")
        lines.append("dashboard_tab=\(model.dashboardTab.rawValue)")
        lines.append("history_warm=\(historyWarmLine(usage.historyWarmPhase))")
        lines.append("usage_refresh_phase=\(usageRefreshLine(presentation.usageRefreshPhase))")
        lines.append("usage_series_phase=\(seriesPhaseLine(usage.phase))")
        lines.append("usage_cards_count=\(model.usageBySeat.count)")
        let plans = model.usageBySeat.values.map(\.plan.name).sorted().joined(separator: "|")
        lines.append("usage_card_plans=\(plans)")
        if let auto = model.usageBySeat.values.map(\.period.usage.autoPercentUsed.percent).sorted().first {
            lines.append("usage_card_auto=\(Int(auto.rounded()))")
        }
        lines.append("identityPolicy=\(presentation.identityPolicy == .maskEmail ? "maskEmail" : "revealEmail")")
        lines.append("aggregate=\(presentation.aggregateLine)")
        lines.append("menuBar=\(presentation.menuBarLabel)")
        lines.append("worstAttention=\(presentation.worstAttention.shortTitle)")
        lines.append("connectedCount=\(presentation.connectedAccounts.count)")
        lines.append("addAccount=\(addAccountLine(presentation.addAccount))")
        lines.append("ideSwitch=\(presentation.ideSwitchPhase.traceName)")
        lines.append("switch_trace=\(FileAccountSwitchTrace.defaultFileURL.path)")
        if let summary = presentation.focusedSeat?.focusedSummaryLine {
            lines.append("focusedSummary=\(summary)")
        }
        for seat in presentation.connectedAccounts {
            lines.append(seatLine(seat))
        }
        lines.append(contentsOf: usageLines(usage))
        let joined = lines.joined(separator: "\n") + "\n"
        if presentation.identityPolicy == .maskEmail, joined.contains("@") {
            return joined + "ASSERT_FAIL contains_at_under_mask\n"
        }
        if presentation.connectedAccounts.contains(where: { $0.auth == .signedOut }) {
            return joined + "ASSERT_FAIL empty_account_in_connected\n"
        }
        return joined + "VERIFY_PRESENTATION_OK\n"
    }

    private static func usageLines(_ usage: UsageSeriesCoordinator) -> [String] {
        var lines: [String] = []
        lines.append("usage_metric=\(usage.resolvedMetric.chartTitle)")
        lines.append("usage_cost_available=\(usage.costAvailable)")
        let scopes = usage.scopeOptions.map(\.1)
        lines.append("usage_scope_options=\(scopes.joined(separator: "|"))")
        let selected = usage.scopeOptions.first(where: { $0.0 == usage.scope })?.1
            ?? UsageScopeLabels.label(for: usage.scope, accountLabel: nil)
        lines.append("usage_scope_selected=\(selected)")
        lines.append("usage_timeline=\(usage.rangeTitle)")
        lines.append("usage_timeline_can_next=\(usage.canGoNext)")
        lines.append("usage_all_time_available=\(usage.allTimeBound != nil)")
        if let series = usage.series {
            let tokenSum = series.points.reduce(Int64(0)) { $0 + $1.tokens }
            let nonEmpty = series.points.filter { $0.tokens > 0 || ($0.spendCents ?? 0) > 0 }.count
            lines.append("usage_graph=present")
            lines.append("usage_point_count=\(series.points.count)")
            lines.append("usage_token_sum=\(tokenSum)")
            lines.append("usage_non_empty_points=\(nonEmpty)")
            lines.append("usage_range=\(series.rangeStart.isoDate)..\(series.rangeEnd.isoDate)")
            if let caption = series.coverage.caption {
                lines.append("usage_coverage=\(caption)")
            } else {
                lines.append("usage_coverage=complete")
            }
            lines.append("usage_ax=\(usage.accessibilityDescriptor)")
        } else {
            lines.append("usage_graph=absent")
        }
        return lines
    }

    private static func addAccountLine(_ addAccount: AddAccountPresentation) -> String {
        switch addAccount {
        case .available(let title, let seatID):
            return "available title=\(title) seat=\(seatID.rawValue) ax=\(addAccount.accessibilityLabel)"
        case .signingIn(let seatID, let canCancel, let isFinishing):
            return "signingIn seat=\(seatID.rawValue) canCancel=\(canCancel) finishing=\(isFinishing) ax=\(addAccount.accessibilityLabel)"
        case .failed(let title, let seatID, let message):
            return "failed title=\(title) seat=\(seatID.rawValue) message=\(message) ax=\(addAccount.accessibilityLabel)"
        }
    }

    private static func seatLine(_ seat: SeatPresentation) -> String {
        let auto = seat.autoPercent.map { "\(Int($0.percent.rounded()))" } ?? "nil"
        let api = seat.apiPercent.map { "\(Int($0.percent.rounded()))" } ?? "nil"
        let onDemand = seat.onDemand?.spendLine ?? "nil"
        let pill = seat.pill?.shortTitle ?? "nil"
        let plan = seat.planName ?? "nil"
        let email = seat.revealedEmail?.value ?? "nil"
        return [
            "seat=\(seat.seatID.rawValue)",
            "label=\(seat.label.text)",
            "auth=\(seat.authTitle)",
            "plan=\(plan)",
            "\(UsagePoolLabel.cursorModels.title)=\(auto)%",
            "\(UsagePoolLabel.otherModels.title)=\(api)%",
            "onDemand=\(onDemand)",
            "pill=\(pill)",
            "revealedEmail=\(email)",
            "rootMenu=\(seat.rootMenuTitle)",
            "ax=\(seat.accessibilityLabel)",
        ].joined(separator: " ")
    }

    private static func historyWarmLine(_ phase: HistoryWarmPhase) -> String {
        switch phase {
        case .idle:
            return "idle"
        case .warming(let completed, let target):
            return "warming \(completed)/\(target)"
        case .settled(let months):
            return "settled \(months)"
        case .cancelled:
            return "cancelled"
        }
    }

    private static func usageRefreshLine(_ phase: UsageRefreshPhase) -> String {
        switch phase {
        case .idle:
            return "idle"
        case .refreshing(let scope):
            switch scope {
            case .all:
                return "refreshing all"
            case .seat(let seatID):
                return "refreshing \(seatID.rawValue)"
            }
        case .settled:
            return "settled"
        }
    }

    private static func seriesPhaseLine(_ phase: UsageSeriesRefreshPhase) -> String {
        switch phase {
        case .idle:
            return "idle"
        case .refreshing:
            return "refreshing"
        case .settled:
            return "settled"
        case .failed:
            return "failed"
        }
    }
}
