import CursorBarDomain
import SwiftUI

struct DashboardSortHeader: View {
    let title: String
    var isActive: Bool
    var direction: DashboardSortDirection
    var alignment: HorizontalAlignment = .leading
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                if isActive {
                    Image(systemName: direction == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .font(CursorProfile.Font.statLabel)
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if isActive {
            let order = direction == .ascending ? "ascending" : "descending"
            return "\(title), sorted \(order)"
        }
        return "Sort by \(title)"
    }
}

struct DashboardPercentMeter: View {
    let percent: PercentUsed?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let percent {
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(CursorProfile.emptyCell(colorScheme))
                        if let width = FiniteLayout.dimension(
                            geo.size.width * CGFloat(min(max(percent.unitFraction, 0), 1))
                        ) {
                            Capsule()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.40 : 0.22))
                                .frame(width: width)
                        }
                    }
                }
                .frame(height: 4)
                Text("\(Int(percent.percent.rounded()))%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .frame(width: 36, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int(percent.percent.rounded())) percent")
        } else {
            Text("—")
                .font(CursorProfile.Font.meta)
                .foregroundStyle(.secondary)
                .accessibilityLabel("No usage")
        }
    }
}
