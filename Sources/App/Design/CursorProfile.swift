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
    static let tableMaxWidth: CGFloat = 960
    static let railWidth: CGFloat = 176

    enum Font {
        /// Live cursor.com/@jpl h1: 20px / 600, system-ui.
        static let display = SwiftUI.Font.system(size: 20, weight: .semibold)
        static let section = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let heroMetric = SwiftUI.Font.system(size: 28, weight: .semibold).monospacedDigit()
        static let statValue = SwiftUI.Font.system(size: 20, weight: .semibold).monospacedDigit()
        static let statLabel = SwiftUI.Font.system(size: 11, weight: .regular)
        static let handle = SwiftUI.Font.system(size: 13, weight: .regular)
        /// Table body. 13 regular, system default design.
        static let table = SwiftUI.Font.system(size: 13, weight: .regular, design: .default)
        static let meta = SwiftUI.Font.system(size: 12, weight: .regular)
        static let pill = SwiftUI.Font.system(size: 11, weight: .medium)
        static let tooltipValue = SwiftUI.Font.system(size: 11, weight: .semibold).monospacedDigit()
        static let tooltipMeta = SwiftUI.Font.system(size: 11, weight: .medium)
        static let axisEdge = SwiftUI.Font.system(size: 12, weight: .semibold)
    }

    static func page(_ scheme: ColorScheme) -> Color {
        chrome(scheme)
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

    /// cursor.com/@jpl: `color-mix(in srgb, accent N%, chrome)`.
    static func activityFill(normalized: Double, scheme: ColorScheme) -> Color {
        let t = min(max(normalized, 0), 1)
        if t <= 0 { return emptyCell(scheme) }
        if t < 0.25 { return mixAccent(0.40, scheme: scheme) }
        if t < 0.50 { return mixAccent(0.58, scheme: scheme) }
        if t < 0.75 { return mixAccent(0.76, scheme: scheme) }
        return chartAccent
    }

    static func mixAccent(_ amount: Double, scheme: ColorScheme) -> Color {
        let keep = min(max(amount, 0), 1)
        let fade = 1 - keep
        let chrome: Double = scheme == .dark ? 20.0 / 255.0 : 248.0 / 255.0
        return Color(
            red: (245.0 / 255.0) * keep + chrome * fade,
            green: (78.0 / 255.0) * keep + chrome * fade,
            blue: 0 * keep + chrome * fade
        )
    }

    static func accountTint(index: Int) -> Color {
        let tints = [peach, peachMid, peachDeep, Color(red: 0.90, green: 0.58, blue: 0.40), Color(red: 0.52, green: 0.36, blue: 0.28)]
        return tints[index % tints.count]
    }

    static func accountTint(for seatID: SeatID) -> Color {
        accountTint(index: UsageAccountChartColor.index(for: seatID))
    }

    /// Stable chip color so table and list avatars match when no photo URL exists.
    static func avatarFill(seed: String, scheme: ColorScheme) -> Color {
        let hash = seed.unicodeScalars.reduce(into: 0) { partial, scalar in
            partial = partial &* 31 &+ Int(scalar.value)
        }
        let palette: [Color] = [
            Color(red: 0.86, green: 0.45, blue: 0.28),
            Color(red: 0.78, green: 0.36, blue: 0.20),
            Color(red: 0.62, green: 0.40, blue: 0.28),
            Color(red: 0.42, green: 0.48, blue: 0.58),
            Color(red: 0.32, green: 0.52, blue: 0.48),
            Color(red: 0.52, green: 0.38, blue: 0.56),
            Color(red: 0.70, green: 0.50, blue: 0.28),
            Color(red: 0.36, green: 0.42, blue: 0.52),
        ]
        let color = palette[abs(hash) % palette.count]
        return scheme == .dark ? color.opacity(0.88) : color
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
    var pictureURL: URL? = nil
    var size: CGFloat = CursorProfile.avatarSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Text(initial)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(initialsColor)
                .frame(width: size, height: size)
                .background(avatarFill)
            if let pictureURL {
                ProfilePictureImage(url: pictureURL)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initial: String {
        ProfileInitial.letter(from: name)
    }

    private var avatarFill: Color {
        CursorProfile.avatarFill(seed: name, scheme: colorScheme)
    }

    private var initialsColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.white
    }
}

/// cursor.com/@jpl token-graph hover card.
struct CursorProfileHoverCard: View {
    let title: String
    let subtitle: String
    var showsPointer: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CursorProfile.tertiaryText(colorScheme))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CursorProfile.chrome(colorScheme))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(CursorProfile.quaternaryBorder(colorScheme), lineWidth: 1)
            }
            if showsPointer {
                CursorProfileHoverPointer()
                    .fill(CursorProfile.chrome(colorScheme))
                    .frame(width: 10, height: 6)
                    .overlay {
                        CursorProfileHoverPointer()
                            .stroke(CursorProfile.quaternaryBorder(colorScheme), lineWidth: 1)
                    }
                    .offset(y: -1)
            }
        }
        .fixedSize()
        .allowsHitTesting(false)
    }
}

private struct CursorProfileHoverPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
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
