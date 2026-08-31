import CursorBarDomain
import SwiftUI

/// Two-line root-menu account label. Email first, Active as a trailing pill.
struct AccountMenuRow: View {
    let model: AccountMenuRowModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            primaryLine
            secondaryLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .help(model.helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    private var primaryLine: some View {
        HStack(spacing: 6) {
            Text(model.primaryName)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            if model.showsActiveIDE {
                ActiveMenuMarker()
            }
        }
    }

    private var secondaryLine: some View {
        Text(model.secondarySummary)
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(.primary.opacity(contrast == .increased ? 0.84 : 0.72))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }
}

/// Light blue pill, same idea as a "New" badge. No checkmark. Email stays the title.
struct ActiveMenuMarker: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("Active")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(labelColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(fillColor)
            )
            .overlay {
                if contrast == .increased {
                    Capsule(style: .continuous)
                        .strokeBorder(labelColor, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }

    private var labelColor: Color {
        if contrast == .increased {
            return Color.blue
        }
        return colorScheme == .dark
            ? Color(red: 0.62, green: 0.78, blue: 1.0)
            : Color(red: 0.16, green: 0.38, blue: 0.86)
    }

    private var fillColor: Color {
        if contrast == .increased {
            return Color.blue.opacity(0.22)
        }
        return colorScheme == .dark
            ? Color.blue.opacity(0.28)
            : Color(red: 0.82, green: 0.90, blue: 1.0)
    }
}

/// Read-only account facts. One menu view so AppKit does not draw each line as a disabled item.
struct AccountMenuDetailHeader: View {
    let seat: SeatPresentation
    let row: AccountMenuRowModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(row.primaryName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                if seat.isDesktopBound {
                    ActiveMenuMarker()
                }
            }

            Text(seat.authTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary.opacity(mutedOpacity))

            Text(row.secondarySummary)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.primary.opacity(mutedOpacity))

            if let onDemand = seat.onDemand {
                Text(onDemand.spendLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary.opacity(mutedOpacity))
            }

            if let credits = seat.credits, case .present(let balance, _, _) = credits {
                Text("Credits $\(formatCents(balance.cents))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary.opacity(mutedOpacity))
            }

            if let pill = seat.pill {
                Text(pill.explanation)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary.opacity(mutedOpacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .allowsHitTesting(false)
    }

    private var mutedOpacity: Double {
        contrast == .increased ? 0.84 : 0.72
    }

    private func formatCents(_ cents: Int64) -> String {
        String(format: "%.2f", Double(cents) / 100.0)
    }
}

/// Footer CTA. Distinct from account rows (plus affordance, no metrics/pill).
struct ConnectAccountMenuRow: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "plus")
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}
