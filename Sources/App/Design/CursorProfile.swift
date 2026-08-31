import CursorBarDomain
import SwiftUI

/// Visual language from cursor.com public profiles. High-contrast paper, one peach accent.
enum CursorProfile {
    static let peach = Color(red: 1.0, green: 0.702, blue: 0.600)
    static let peachMid = Color(red: 0.965, green: 0.545, blue: 0.365)
    static let peachDeep = Color(red: 0.78, green: 0.36, blue: 0.20)
    /// cursor.com profile `--color-theme-accent` (#f54e00).
    static let chartAccent = Color(red: 245.0 / 255.0, green: 78.0 / 255.0, blue: 0)

    static let pagePadding: CGFloat = 32
    static let sectionSpacing: CGFloat = 28
    static let cardPadding: CGFloat = 16
    static let radius: CGFloat = 8
    static let avatarSize: CGFloat = 40
    static let columnMaxWidth: CGFloat = 720
    static let tableMaxWidth: CGFloat = 880
    static let railWidth: CGFloat = 176

    enum Font {
        /// Live cursor.com/@jpl h1: 20px / 600, system-ui.
        static let display = SwiftUI.Font.system(size: 20, weight: .semibold)
        static let section = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let heroMetric = SwiftUI.Font.system(size: 28, weight: .semibold).monospacedDigit()
        static let statValue = SwiftUI.Font.system(size: 20, weight: .semibold).monospacedDigit()
        static let statLabel = SwiftUI.Font.system(size: 11, weight: .regular)
        static let handle = SwiftUI.Font.system(size: 13, weight: .regular)
        static let meta = SwiftUI.Font.system(size: 12, weight: .regular)
        static let pill = SwiftUI.Font.system(size: 11, weight: .medium)
        static let tooltipValue = SwiftUI.Font.system(size: 11, weight: .semibold).monospacedDigit()
        static let tooltipMeta = SwiftUI.Font.system(size: 11, weight: .medium)
        static let axisEdge = SwiftUI.Font.system(size: 12, weight: .semibold)
    }

    static func page(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 20.0 / 255.0, green: 20.0 / 255.0, blue: 20.0 / 255.0)
            : Color.white
    }

    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 24.0 / 255.0, green: 24.0 / 255.0, blue: 24.0 / 255.0)
            : Color.white
    }

    /// Live profile `--bg-chrome` (#141414 dark / #f8f8f8 light).
    static func chrome(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 20.0 / 255.0, green: 20.0 / 255.0, blue: 20.0 / 255.0)
            : Color(red: 248.0 / 255.0, green: 248.0 / 255.0, blue: 248.0 / 255.0)
    }

    static func elevated(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 24.0 / 255.0, green: 24.0 / 255.0, blue: 24.0 / 255.0)
            : Color(red: 248.0 / 255.0, green: 248.0 / 255.0, blue: 248.0 / 255.0)
    }

    static func tertiaryText(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(0.6)
    }

    /// Hover rule (`bg-quaternary`, 6% in light).
    static func quaternaryFill(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(scheme == .dark ? 0.10 : 0.06)
    }

    /// Plot baseline and tooltip border (`border-quaternary`, 4% in light).
    static func quaternaryBorder(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(scheme == .dark ? 0.08 : 0.04)
    }

    static func emptyCell(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.055)
    }

    static func hairline(_ scheme: ColorScheme, highContrast: Bool) -> Color {
        if highContrast {
            return Color.primary.opacity(scheme == .dark ? 0.55 : 0.35)
        }
        return Color.primary.opacity(scheme == .dark ? 0.12 : 0.08)
    }

    /// Live profile fill: `--color-theme-accent` at 12% (solid, no gradient).
    static func areaFill(_ scheme: ColorScheme, highContrast: Bool = false) -> Color {
        let opacity: Double
        if highContrast {
            opacity = scheme == .dark ? 0.28 : 0.20
        } else {
            opacity = scheme == .dark ? 0.18 : 0.12
        }
        return chartAccent.opacity(opacity)
    }

    static func lineStroke(highContrast: Bool) -> Color {
        highContrast ? peachDeep : chartAccent
    }

    static func activityFill(normalized: Double, scheme: ColorScheme) -> Color {
        let t = min(max(normalized, 0), 1)
        if t <= 0 { return emptyCell(scheme) }
        if t < 0.34 { return peach.opacity(scheme == .dark ? 0.55 : 0.70) }
        if t < 0.67 { return peachMid }
        return peachDeep
    }

    static func accountTint(index: Int) -> Color {
        let tints = [peach, peachMid, peachDeep, Color(red: 0.90, green: 0.58, blue: 0.40), Color(red: 0.52, green: 0.36, blue: 0.28)]
        return tints[index % tints.count]
    }

    static func accountTint(for seatID: SeatID) -> Color {
        accountTint(index: UsageAccountChartColor.index(for: seatID))
    }
}

struct CursorProfileStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(CursorProfile.Font.statLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(CursorProfile.Font.statValue)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

struct CursorProfileAvatar: View {
    let name: String
    var size: CGFloat = CursorProfile.avatarSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(CursorProfile.emptyCell(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = name.split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

struct CursorProfilePill: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(title)
            .font(CursorProfile.Font.pill)
            .foregroundStyle(.primary.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        CursorProfile.hairline(colorScheme, highContrast: contrast == .increased),
                        lineWidth: contrast == .increased ? 1.5 : 1
                    )
            }
    }
}

struct CursorProfilePrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(colorScheme == .dark ? Color.white : Color.black)
                    .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.35)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.snappy(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct CursorProfilePaper: ViewModifier {
    var cornerRadius: CGFloat = CursorProfile.radius
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(CursorProfile.paper(colorScheme))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        CursorProfile.hairline(colorScheme, highContrast: contrast == .increased),
                        lineWidth: contrast == .increased ? 1.5 : 1
                    )
            }
    }
}

extension View {
    func cursorProfilePaper(cornerRadius: CGFloat = CursorProfile.radius) -> some View {
        modifier(CursorProfilePaper(cornerRadius: cornerRadius))
    }
}
