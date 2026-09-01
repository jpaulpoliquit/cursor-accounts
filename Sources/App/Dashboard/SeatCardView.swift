import CursorBarDomain
import SwiftUI

enum DashboardSeatSurface: Equatable {
    case card
    case row
}

struct SeatCardView: View {
    let seat: SeatPresentation
    let hardLimitPhase: SetHardLimitPhase
    let model: AppModel
    var surface: DashboardSeatSurface = .card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var projection: DashboardSeatControlsProjection {
        .project(seat: seat, hardLimitPhase: hardLimitPhase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                CursorProfileAvatar(
                    name: seat.dashboardTitle,
                    pictureURL: seat.pictureURL,
                    size: 36
                )
                Text(seat.dashboardTitle)
                    .font(CursorProfile.Font.section)
                    .lineLimit(2)
                if projection.showsActiveIndicator {
                    ActiveMenuMarker()
                }
                if let plan = seat.planBadgeTitle, !plan.isEmpty {
                    CursorProfilePill(title: plan)
                }
                if seat.isTeamAccount, seat.planBadgeTitle?.caseInsensitiveCompare("Team") != .orderedSame {
                    CursorProfilePill(title: "Team")
                }
                if let price = seat.planPrice, !price.isEmpty {
                    Text(price)
                        .font(CursorProfile.Font.meta)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                DashboardAccountActionsMenu(
                    seat: seat,
                    hardLimitPhase: hardLimitPhase,
                    model: model
                )
            }

            if let subtitle = seat.identitySubtitle {
                Text(subtitle)
                    .font(CursorProfile.Font.handle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if seat.auth == .signedIn || seat.auth == .needsReauth {
                detailBlock
            }

            DashboardSeatControls(
                seat: seat,
                hardLimitPhase: hardLimitPhase,
                model: model
            )

            if surface == .card {
                Spacer(minLength: 0)
            }
        }
        .modifier(DashboardSeatSurfaceChrome(surface: surface))
        .animation(Motion.gentle(reduceMotion: reduceMotion), value: seat.autoPercent?.percent)
        .animation(Motion.gentle(reduceMotion: reduceMotion), value: hardLimitPhase)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(projection.cardAccessibilityLabel)
    }

    @ViewBuilder
    private var detailBlock: some View {
        if let reset = seat.resetDate {
            Text("Resets \(reset.formatted(date: .abbreviated, time: .omitted))")
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
        }

        if let credits = seat.credits, case .present(let balance, _, _) = credits {
            Text("Credits $\(String(format: "%.2f", Double(balance.cents) / 100)) remaining")
                .font(CursorProfile.Font.meta)
        }

        if seat.autoPercent != nil || seat.apiPercent != nil {
            Text("Included in plan")
                .font(CursorProfile.Font.statLabel)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            if let auto = seat.autoPercent {
                UsageBar(title: UsagePoolLabel.cursorModels.title, percent: auto)
            }
            if let api = seat.apiPercent {
                UsageBar(title: UsagePoolLabel.otherModels.title, percent: api)
            }
        }

        if case .available(let spendRow, _, _, _, let writesDisabled) = projection.onDemand {
            let openEditor = {
                model.presentOnDemandEditor(seatID: seat.seatID)
            }
            switch spendRow {
            case .hidden:
                OnDemandSpendBar(
                    amountText: "On-demand off",
                    progressFraction: nil,
                    showsTrack: false,
                    action: writesDisabled ? nil : openEditor
                )
            case .fixed(let amountText, let fraction):
                OnDemandSpendBar(
                    amountText: amountText,
                    progressFraction: fraction,
                    showsTrack: true,
                    action: writesDisabled ? nil : openEditor
                )
            case .unlimited(let amountText):
                OnDemandSpendBar(
                    amountText: amountText ?? "Unlimited",
                    progressFraction: nil,
                    showsTrack: false,
                    action: writesDisabled ? nil : openEditor
                )
            }
        }

        if let pill = projection.statusPill {
            StatusCapsule(pill: pill)
        }
    }
}

private struct OnDemandSpendBar: View {
    let amountText: String
    let progressFraction: Double?
    let showsTrack: Bool
    var action: (() -> Void)? = nil

    var body: some View {
        let bar = VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("On-demand")
                    .font(CursorProfile.Font.meta)
                Spacer()
                Text(amountText)
                    .font(CursorProfile.Font.meta)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if showsTrack {
                ProfileUsageTrack(fraction: progressFraction)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("On-demand \(amountText)")

        if let action {
            Button(action: action) {
                bar
            }
            .buttonStyle(.plain)
            .help("Edit on-demand")
            .accessibilityHint("Edits on-demand")
        } else {
            bar
        }
    }
}

private struct UsageBar: View {
    let title: String
    let percent: PercentUsed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(CursorProfile.Font.meta)
                Spacer()
                Text("\(Int(percent.percent.rounded()))%")
                    .font(CursorProfile.Font.meta)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProfileUsageTrack(fraction: percent.unitFraction, overflowCeiling: 1.2)
                .animation(Motion.snappy(reduceMotion: reduceMotion), value: percent.percent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(Int(percent.percent.rounded())) percent")
    }
}

private struct ProfileUsageTrack: View {
    var fraction: Double?
    var overflowCeiling: Double = 1
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(CursorProfile.emptyCell(colorScheme))
                if let fraction,
                   let width = FiniteLayout.dimension(
                       geo.size.width * CGFloat(min(max(fraction, 0), overflowCeiling))
                   )
                {
                    Capsule()
                        .fill(CursorProfile.peach)
                        .frame(width: width)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
