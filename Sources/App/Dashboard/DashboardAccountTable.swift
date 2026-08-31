import CursorBarDomain
import SwiftUI

struct DashboardAccountTable: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hoveredID: SeatID?

    private var seats: [SeatPresentation] {
        DashboardAccountOrdering.sorted(
            model.presentation.connectedAccounts,
            by: model.accountSort,
            direction: model.accountSortDirection
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if seats.isEmpty {
                Text("No accounts connected")
                    .font(CursorProfile.Font.meta)
                    .foregroundStyle(.secondary)
                    .padding(18)
            } else {
                ForEach(seats) { seat in
                    row(seat)
                }
            }
        }
        .background(CursorProfile.paper(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    CursorProfile.hairline(colorScheme, highContrast: contrast == .increased),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accounts table")
    }

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Color.clear.frame(width: 28)
                sortHeader("Name", .name, alignment: .leading)
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
            Text("Plan")
                .font(CursorProfile.Font.statLabel)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            sortHeader("Cursor", .usage, alignment: .trailing)
                .frame(width: 100, alignment: .trailing)
            sortHeader("Other", .usage, alignment: .trailing)
                .frame(width: 100, alignment: .trailing)
            sortHeader("On-demand", .onDemand, alignment: .trailing)
                .frame(width: 108, alignment: .trailing)
            sortHeader("Resets", .reset, alignment: .trailing)
                .frame(width: 64, alignment: .trailing)
            Color.clear.frame(width: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { rowRule }
    }

    private func row(_ seat: SeatPresentation) -> some View {
        let hovered = hoveredID == seat.seatID
        return HStack(spacing: 16) {
            nameCell(seat)
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
            Text(seat.planName?.capitalized ?? "—")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(seat.planName == nil ? Color.secondary : Color.primary)
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)
            DashboardPercentMeter(percent: seat.autoPercent)
                .frame(width: 100, alignment: .trailing)
            DashboardPercentMeter(percent: seat.apiPercent)
                .frame(width: 100, alignment: .trailing)
            Text(seat.onDemand?.spendLine ?? "—")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(seat.onDemand == nil ? Color.secondary : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 108, alignment: .trailing)
            Text(resetLabel(seat.resetDate))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(seat.resetDate == nil ? Color.secondary : Color.primary)
                .frame(width: 64, alignment: .trailing)
            DashboardAccountActionsMenu(
                seat: seat,
                hardLimitPhase: model.presentation.setHardLimitPhase,
                model: model
            )
            .frame(width: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(hovered ? CursorProfile.quaternaryFill(colorScheme) : Color.clear)
        .overlay(alignment: .bottom) { rowRule }
        .onHover { hovering in
            hoveredID = hovering ? seat.seatID : (hoveredID == seat.seatID ? nil : hoveredID)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibility(seat))
    }

    private func nameCell(_ seat: SeatPresentation) -> some View {
        HStack(spacing: 10) {
            CursorProfileAvatar(name: seat.dashboardTitle, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(seat.dashboardTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if seat.isDesktopBound {
                        ActiveMenuMarker()
                    }
                }
                if let email = seat.revealedEmail, email.value != seat.dashboardTitle {
                    Text(email.value)
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var rowRule: some View {
        Rectangle()
            .fill(CursorProfile.hairline(colorScheme, highContrast: contrast == .increased))
            .frame(height: 1)
            .padding(.leading, 52)
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
        if let email = seat.revealedEmail, email.value != seat.dashboardTitle {
            parts.append(email.value)
        }
        if let plan = seat.planName {
            parts.append(plan)
        }
        if let auto = seat.autoPercent {
            parts.append("\(UsagePoolLabel.cursorModels.title) \(Int(auto.percent.rounded())) percent")
        }
        if let api = seat.apiPercent {
            parts.append("\(UsagePoolLabel.otherModels.title) \(Int(api.percent.rounded())) percent")
        }
        if let onDemand = seat.onDemand {
            parts.append(onDemand.spendLine)
        }
        if let reset = seat.resetDate {
            parts.append("resets \(resetLabel(reset))")
        }
        return parts.joined(separator: ", ")
    }
}
