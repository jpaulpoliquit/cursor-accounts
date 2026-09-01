import CursorBarDomain
import SwiftUI

/// Compact rate-change line: delta chip, from → to, month window. Not a second Rate column.
struct ModelRateChangeLabel: View {
    let change: ModelRateChange
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if change.direction != .flat, let percent = change.percent {
                deltaChip(percent: percent)
            }
            rates
            Text(change.monthRangeLabel)
                .foregroundStyle(.tertiary)
                .layoutPriority(0)
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .help(
            "Implied Cursor rate from \(change.startMonthLabel) to \(change.endMonthLabel). Input, output, and cache tokens are mixed."
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(change.accessibilityLabel)
    }

    private func deltaChip(percent: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: change.direction == .down ? "arrow.down" : "arrow.up")
                .font(.system(size: 8, weight: .bold))
            Text("\(percent)%")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(CursorProfile.quaternaryFill(colorScheme))
        )
        .layoutPriority(1)
    }

    @ViewBuilder
    private var rates: some View {
        if change.direction == .flat {
            Text("\(change.endRateLabel) / 1M")
                .foregroundStyle(.secondary)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(change.startRateLabel)
                    .foregroundStyle(.tertiary)
                Text("→")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 11, weight: .regular))
                Text(change.endRateLabel)
                    .foregroundStyle(.primary)
                Text("/ 1M")
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)
        }
    }
}
