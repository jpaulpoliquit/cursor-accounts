import SwiftUI

/// Newton admin grouped-table chrome. Header is a full-width slab, not a data row.
enum DashboardTableGroupMetrics {
    static let headerHeight: CGFloat = 48
    static let lineHeaderHeight: CGFloat = 36
    static let columnHeaderHeight: CGFloat = 40
    /// `pl-6` — first column lines up with the group title, not the chevron.
    static let nestedInset: CGFloat = 24
    static let chevronWidth: CGFloat = 16
    static let edgeInset: CGFloat = 14
}

enum DashboardTableGroupKind {
    case family
    case line

    var height: CGFloat {
        switch self {
        case .family: DashboardTableGroupMetrics.headerHeight
        case .line: DashboardTableGroupMetrics.lineHeaderHeight
        }
    }

    var titleFont: Font {
        switch self {
        case .family: .system(size: 13, weight: .semibold)
        case .line: .system(size: 12, weight: .semibold)
        }
    }

    var leading: CGFloat {
        switch self {
        case .family: DashboardTableGroupMetrics.edgeInset
        case .line: DashboardTableGroupMetrics.edgeInset + DashboardTableGroupMetrics.nestedInset
        }
    }
}

/// Collapse control + title + count. Full-width slab, no metric cells.
struct DashboardTableGroupHeader: View {
    let title: String
    let countLabel: String
    var kind: DashboardTableGroupKind = .family
    var collapsed: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: DashboardTableGroupMetrics.chevronWidth, height: 16)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .animation(Motion.snappy(reduceMotion: reduceMotion), value: collapsed)
                    .accessibilityHidden(true)
                Text(title)
                    .font(kind.titleFont)
                    .lineLimit(1)
                Text(countLabel)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, kind.leading)
            .padding(.trailing, DashboardTableGroupMetrics.edgeInset)
            .padding(.top, kind == .family ? 8 : 0)
            .frame(height: kind.height, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(title), \(countLabel)")
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        .accessibilityHint(collapsed ? "Expands the \(title) group" : "Collapses the \(title) group")
    }
}
