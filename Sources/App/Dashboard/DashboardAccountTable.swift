import CursorBarDomain
import SwiftUI

struct DashboardAccountTable: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hoveredID: SeatID?

    private var listing: DashboardAccountFilter.Listing {
        DashboardAccountFilter.Listing.make(
            seats: model.presentation.connectedAccounts,
            query: model.accountFilter
        )
    }

    private var seats: [SeatPresentation] {
        DashboardAccountOrdering.sorted(
            listing.visible,
            by: model.accountSort,
            direction: model.accountSortDirection
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let empty = listing.emptyReason {
                Text(empty.message)
                    .font(CursorProfile.Font.table)
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                ForEach(seats) { seat in
                    row(seat)
                }
            }
        }
        .background(CursorProfile.paper(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    CursorProfile.hairline(colorScheme, highContrast: contrast == .increased),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accounts table")
    }

    private var headerTrailing: some View {
        Color.clear.frame(width: 32, height: 1)
    }

    private var photoColumn: some View {
        Color.clear
            .frame(width: CursorProfile.tableAvatarSize, height: 1)
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            photoColumn
            sortHeader("Name", .name, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortHeader(leadingUsageHeader, .usage, alignment: .trailing)
                .frame(width: 64, alignment: .trailing)
            Text(trailingUsageHeader)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            sortHeader("On-demand", .onDemand, alignment: .trailing)
                .frame(width: 100, alignment: .trailing)
            sortHeader("Resets", .reset, alignment: .trailing)
                .frame(width: 64, alignment: .trailing)
            headerTrailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { rowRule }
    }

    private func row(_ seat: SeatPresentation) -> some View {
        let hovered = hoveredID == seat.seatID
        return HStack(alignment: .center, spacing: 10) {
            photoCell(seat)
            nameCell(seat)
                .frame(maxWidth: .infinity, alignment: .leading)
            usageLeadingCell(seat)
            usageTrailingCell(seat)
            onDemandCell(seat)
            Text(resetLabel(seat.resetDate))
                .font(CursorProfile.Font.table.monospacedDigit())
                .foregroundStyle(seat.resetDate == nil ? Color.secondary : Color.primary)
                .frame(width: 64, alignment: .trailing)
            DashboardAccountActionsMenu(
                seat: seat,
                hardLimitPhase: model.presentation.setHardLimitPhase,
                model: model
            )
            .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52, alignment: .center)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovered ? CursorProfile.quaternaryFill(colorScheme) : Color.clear)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .overlay(alignment: .bottom) { rowRule }
        .onHover { hovering in
            hoveredID = hovering ? seat.seatID : (hoveredID == seat.seatID ? nil : hoveredID)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibility(seat))
        .accessibilityAction(named: "Edit on-demand") {
            if canEditOnDemand(seat) {
                model.presentOnDemandEditor(seatID: seat.seatID)
            }
        }
    }

    private func photoCell(_ seat: SeatPresentation) -> some View {
        CursorProfileAvatar(
            name: seat.dashboardTitle,
            pictureURL: seat.pictureURL,
            size: CursorProfile.tableAvatarSize
        )
        .frame(width: CursorProfile.tableAvatarSize, height: CursorProfile.tableAvatarSize)
        .fixedSize()
    }

    private func nameCell(_ seat: SeatPresentation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(seat.dashboardTitle)
                    .font(CursorProfile.Font.table.weight(.semibold))
                    .lineLimit(1)
                    .onTapGesture {
                        if seat.auth == .signedIn || seat.auth == .needsReauth {
                            model.presentLabelEditor(seatID: seat.seatID)
                        }
                    }
                if seat.isDesktopBound {
                    ActiveMenuMarker()
                }
                if let plan = seat.planBadgeTitle, !plan.isEmpty {
                    CursorProfilePill(title: plan)
                }
                if seat.isTeamAccount, seat.planBadgeTitle?.caseInsensitiveCompare("Team") != .orderedSame {
                    CursorProfilePill(title: "Team")
                }
            }
            if let subtitle = seat.identitySubtitle {
                Text(subtitle)
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var leadingUsageHeader: String {
        switch model.accountUsageMetric {
        case .percent: "Cursor"
        case .tokens: "Tokens"
        }
    }

    private var trailingUsageHeader: String {
        switch model.accountUsageMetric {
        case .percent: "API"
        case .tokens: "Reqs"
        }
    }

    private func usageLeadingCell(_ seat: SeatPresentation) -> some View {
        Text(leadingUsageText(seat))
            .font(CursorProfile.Font.table.monospacedDigit())
            .foregroundStyle(leadingUsageText(seat) == "—" ? Color.secondary : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: 64, alignment: .trailing)
    }

    private func usageTrailingCell(_ seat: SeatPresentation) -> some View {
        Text(trailingUsageText(seat))
            .font(CursorProfile.Font.table.monospacedDigit())
            .foregroundStyle(trailingUsageText(seat) == "—" ? Color.secondary : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: 64, alignment: .trailing)
    }

    private func leadingUsageText(_ seat: SeatPresentation) -> String {
        switch model.accountUsageMetric {
        case .percent:
            return percentText(seat.autoPercent)
        case .tokens:
            if let totals = model.usageSeries.insights?.seatActivityTotals(seatID: seat.seatID) {
                return TokenCountFormat.compact(totals.tokens)
            }
            return "—"
        }
    }

    private func trailingUsageText(_ seat: SeatPresentation) -> String {
        switch model.accountUsageMetric {
        case .percent:
            return percentText(seat.apiPercent)
        case .tokens:
            if let totals = model.usageSeries.insights?.seatActivityTotals(seatID: seat.seatID) {
                return TokenCountFormat.compact(Int64(totals.requests))
            }
            return "—"
        }
    }

    private func percentText(_ percent: PercentUsed?) -> String {
        guard let percent else { return "—" }
        return "\(Int(percent.percent.rounded()))%"
    }

    @ViewBuilder
    private func onDemandCell(_ seat: SeatPresentation) -> some View {
        let line = seat.onDemand?.spendLine ?? "—"
        let label = Text(line)
            .font(CursorProfile.Font.table.monospacedDigit())
            .foregroundStyle(seat.onDemand == nil ? Color.secondary : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: 100, alignment: .trailing)
        if canEditOnDemand(seat) {
            Button {
                model.presentOnDemandEditor(seatID: seat.seatID)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .help("Edit on-demand")
            .accessibilityHint("Edits on-demand for \(seat.dashboardTitle)")
        } else {
            label
        }
    }

    private var rowRule: some View {
        Rectangle()
            .fill(CursorProfile.hairline(colorScheme, highContrast: contrast == .increased))
            .frame(height: 1)
    }

    private func sortHeader(
        _ title: String,
        _ sort: DashboardAccountSort,
        alignment: HorizontalAlignment
    ) -> some View {
        DashboardSortHeader(
            title: title,
            isActive: model.accountSort == sort,
            direction: model.accountSortDirection,
            alignment: alignment
        ) {
            let next = DashboardAccountOrdering.nextSelection(
                current: model.accountSort,
                direction: model.accountSortDirection,
                tapped: sort
            )
            model.accountSort = next.0
            model.accountSortDirection = next.1
        }
    }

    private func resetLabel(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func rowAccessibility(_ seat: SeatPresentation) -> String {
        var parts = [seat.dashboardTitle]
        if seat.isDesktopBound {
            parts.append("Active")
        }
        if let subtitle = seat.identitySubtitle {
            parts.append(subtitle)
        }
        if let plan = seat.planBadgeTitle, !plan.isEmpty {
            parts.append(plan)
        }
        if seat.isTeamAccount {
            parts.append("Team")
        }
        switch model.accountUsageMetric {
        case .percent:
            if let auto = seat.autoPercent {
                parts.append("\(UsagePoolLabel.cursorModels.title) \(Int(auto.percent.rounded())) percent")
            }
            if let api = seat.apiPercent {
                parts.append("\(UsagePoolLabel.otherModels.title) \(Int(api.percent.rounded())) percent")
            }
        case .tokens:
            parts.append("Cursor \(leadingUsageText(seat))")
            parts.append("Requests \(trailingUsageText(seat))")
        }
        parts.append(seat.onDemand?.spendLine ?? "On-demand —")
        if let reset = seat.resetDate {
            parts.append("resets \(resetLabel(reset))")
        }
        return parts.joined(separator: ", ")
    }

    private func canEditOnDemand(_ seat: SeatPresentation) -> Bool {
        DashboardSeatControlsProjection.project(
            seat: seat,
            hardLimitPhase: model.presentation.setHardLimitPhase
        ).canPresentOnDemandEditor
    }
}
