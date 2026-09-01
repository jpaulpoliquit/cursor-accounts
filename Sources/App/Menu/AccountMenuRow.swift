import CursorBarDomain
import SwiftUI

/// Root-menu account label. Title carries the Active checkmark because NSMenu flattens custom views.
struct AccountMenuRow: View {
    let model: AccountMenuRowModel

    var body: some View {
        Text(model.rootItemTitle)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityLabel(model.accessibilityLabel)
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

/// One status line. NSMenu renders extra `Text` rows as disabled captions; keep a single fact line.
struct AccountMenuDetailHeader: View {
    let row: AccountMenuRowModel

    var body: some View {
        if !row.submenuStatusLine.isEmpty {
            Text(row.submenuStatusLine)
                .font(.body.weight(.medium).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                .accessibilityLabel(row.submenuStatusLine)
        }
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
