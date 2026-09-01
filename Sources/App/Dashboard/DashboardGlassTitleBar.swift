import CursorBarDomain
import SwiftUI

/// Gray-track pill tabs, same idea as a plan switcher (Pro / Pro+ / Ultra).
struct DashboardProfileTabBar: View {
    @Binding var selection: DashboardTab
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(CursorProfile.emptyCell(colorScheme))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dashboard section")
    }

    private func tabButton(_ tab: DashboardTab) -> some View {
        let selected = tab == selection
        return Button {
            selection = tab
        } label: {
            Text(tab.title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .contentShape(Capsule())
                .background {
                    if selected {
                        Capsule(style: .continuous)
                            .fill(CursorProfile.paper(colorScheme))
                            .shadow(
                                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.10),
                                radius: 2,
                                y: 1
                            )
                    }
                }
        }
        .buttonStyle(DashboardPillTabButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Gray-track pill switcher. Same chrome as the Accounts / Models / Usage tabs.
struct DashboardPillSegmentedControl<Option: Hashable, Item: View>: View {
    @Binding var selection: Option
    let options: [Option]
    var accessibilityName: String
    @ViewBuilder var item: (Option, Bool) -> Item

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    item(option, selected)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Capsule())
                        .background {
                            if selected {
                                Capsule(style: .continuous)
                                    .fill(CursorProfile.paper(colorScheme))
                                    .shadow(
                                        color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.10),
                                        radius: 2,
                                        y: 1
                                    )
                            }
                        }
                }
                .buttonStyle(DashboardPillTabButtonStyle(reduceMotion: reduceMotion))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(CursorProfile.emptyCell(colorScheme))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}

struct DashboardPillTabButtonStyle: ButtonStyle {
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.snappy(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct DashboardPageHeader: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    if showsIdentity {
                        CursorProfileAvatar(
                            name: accountName,
                            pictureURL: activeAccount?.pictureURL,
                            size: 36
                        )
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(accountName)
                                .font(CursorProfile.Font.display)
                                .tracking(-0.3)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            if showsActivePill {
                                ActiveMenuMarker()
                            }
                        }
                        if let email = teaserEmail {
                            Text(email)
                                .font(CursorProfile.Font.handle)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                Spacer(minLength: 16)
                if showsUsageStats {
                    HStack(spacing: 28) {
                        DashboardTeaserStat(
                            label: UsagePoolLabel.cursorModels.compactTitle,
                            percent: activeAccount?.autoPercent
                        )
                        DashboardTeaserStat(
                            label: "API",
                            percent: activeAccount?.apiPercent
                        )
                        if let onDemandLine = onDemandSpendLine, let activeAccount {
                            DashboardTeaserStat(
                                label: "On-demand",
                                value: onDemandLine,
                                action: canEditActiveOnDemand
                                    ? { model.presentOnDemandEditor(seatID: activeAccount.seatID) }
                                    : nil
                            )
                        }
                    }
                    .padding(.top, 2)
                }
            }
            DashboardProfileTabBar(selection: $model.dashboardTab)
                .fixedSize(horizontal: true, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var activeAccount: SeatPresentation? {
        model.presentation.connectedAccounts.first(where: \.isDesktopBound)
    }

    private var showsIdentity: Bool {
        guard let activeAccount else { return false }
        return activeAccount.auth == .signedIn || activeAccount.auth == .needsReauth
    }

    private var accountName: String {
        if showsIdentity, let activeAccount {
            return activeAccount.dashboardTitle
        }
        return "No active account"
    }

    private var showsActivePill: Bool {
        activeAccount != nil
    }

    private var teaserEmail: String? {
        guard let email = activeAccount?.revealedEmail?.value else { return nil }
        if email == accountName { return nil }
        return email
    }

    private var showsUsageStats: Bool {
        activeAccount?.autoPercent != nil
            || activeAccount?.apiPercent != nil
            || onDemandSpendLine != nil
    }

    private var onDemandSpendLine: String? {
        guard let onDemand = activeAccount?.onDemand else { return nil }
        switch onDemand.mode {
        case .off:
            return nil
        case .fixed, .unlimited:
            return onDemand.spendLine
        }
    }

    private var canEditActiveOnDemand: Bool {
        guard let activeAccount else { return false }
        return DashboardSeatControlsProjection.project(
            seat: activeAccount,
            hardLimitPhase: model.presentation.setHardLimitPhase
        ).canPresentOnDemandEditor
    }

}

private struct DashboardTeaserStat: View {
    let label: String
    let value: String
    var action: (() -> Void)? = nil

    init(label: String, percent: PercentUsed?, action: (() -> Void)? = nil) {
        self.label = label
        if let percent {
            value = "\(Int(percent.percent.rounded()))%"
        } else {
            value = "—"
        }
        self.action = action
    }

    init(label: String, value: String, action: (() -> Void)? = nil) {
        self.label = label
        self.value = value
        self.action = action
    }

    var body: some View {
        let stat = VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(CursorProfile.Font.statLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")

        if let action {
            Button(action: action) {
                stat
            }
            .buttonStyle(.plain)
            .help("Edit on-demand")
            .accessibilityHint("Edits on-demand")
        } else {
            stat
        }
    }
}
