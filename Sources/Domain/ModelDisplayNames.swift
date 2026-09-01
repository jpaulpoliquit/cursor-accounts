import Foundation

/// Explicit display names for known modelIntent slugs, plus a robust humanized fallback.
///
/// Family IDs and labels follow Project Newton’s `cursorModelFamilyId` /
/// `CURSOR_MODEL_FAMILY_LABEL` in `cursor-model-picker-groups.ts`.
public enum ModelDisplayNames {
    private static let autoModelIntent = "default"

    private static let known: [String: String] = [
        "cursor-grok-4.5-high-fast": "Cursor Grok 4.5 High Fast",
        "cursor-grok-4.5-high": "Cursor Grok 4.5 High",
        "composer-2.5-fast": "Composer 2.5 Fast",
        "composer-2": "Composer 2",
        "composer-1.5": "Composer 1.5",
        "gpt-5.6-sol-medium": "GPT 5.6 Sol Medium",
        "gpt-5.6-sol-xhigh": "GPT 5.6 Sol XHigh",
        "gpt-5.6-sol-high": "GPT 5.6 Sol High",
        "gpt-5.5-medium": "GPT 5.5 Medium",
        "gpt-5.5-high": "GPT 5.5 High",
        "gpt-5.3-codex": "GPT 5.3 Codex",
        "gpt-5.2": "GPT 5.2",
        "gpt-5.1": "GPT 5.1",
        "gpt-5": "GPT 5",
        "claude-4.6-sonnet-medium-thinking": "Claude 4.6 Sonnet Medium Thinking",
        "claude-4.5-sonnet-thinking": "Claude 4.5 Sonnet Thinking",
        "claude-4.5-opus-high-thinking": "Claude 4.5 Opus High Thinking",
        "claude-4-sonnet": "Claude 4 Sonnet",
        "claude-4-opus": "Claude 4 Opus",
        "o3": "o3",
        "o4-mini": "o4 Mini",
        "default": "Auto",
    ]

    /// Newton family buckets, in `CURSOR_MODEL_FAMILY_IDS` order.
    public enum Family: String, Sendable, CaseIterable, Equatable {
        case auto
        case grok
        case composer
        case claude
        case gpt
        case gemini
        case kimi
        case glm
        case other

        public var title: String {
            switch self {
            case .auto: "Auto"
            case .grok: "Cursor Grok"
            case .composer: "Composer"
            case .claude: "Claude"
            case .gpt: "GPT"
            case .gemini: "Gemini"
            case .kimi: "Kimi"
            case .glm: "GLM"
            case .other: "Other"
            }
        }

        public var symbolName: String {
            switch self {
            case .auto: "sparkles"
            case .grok: "cube.fill"
            case .composer: "square.stack.3d.up.fill"
            case .claude: "asterisk"
            case .gpt: "hexagon.fill"
            case .gemini: "diamond.fill"
            case .kimi: "moon.stars.fill"
            case .glm: "triangle.fill"
            case .other: "cpu"
            }
        }

        /// Classifies from slug and optional display label, same haystack as Newton.
        public static func of(modelIntent: String, displayName: String? = nil) -> Family {
            let id = modelIntent.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.lowercased() == autoModelIntent { return .auto }
            let hay = "\(id) \(displayName ?? "")".lowercased()
            if hay.contains("grok") { return .grok }
            if hay.contains("composer") { return .composer }
            if hay.contains("claude")
                || hay.contains("opus")
                || hay.contains("sonnet")
                || hay.contains("fable")
            {
                return .claude
            }
            if hay.contains("gpt") || hay.contains("codex") { return .gpt }
            if hay.contains("gemini") { return .gemini }
            if hay.contains("kimi") { return .kimi }
            if hay.contains("glm") { return .glm }
            return .other
        }
    }

    /// Generation / line inside a family. Newton `splitCursorModelPickerName` + `dottedAfter`.
    public struct Line: Sendable, Equatable, Hashable, Identifiable {
        public var id: String { title }
        public let title: String
        public let major: Int
        public let minor: Int
        public let hasVersion: Bool
        public let lineRank: Int

        public init(title: String, major: Int, minor: Int, hasVersion: Bool, lineRank: Int) {
            self.title = title
            self.major = major
            self.minor = minor
            self.hasVersion = hasVersion
            self.lineRank = lineRank
        }

        public static func of(
            family: Family,
            modelIntent: String,
            displayName: String
        ) -> Line {
            let hay = spacedHay(modelIntent, displayName)
            switch family {
            case .auto:
                return Line(title: family.title, major: 0, minor: 0, hasVersion: false, lineRank: 0)
            case .other:
                return Line(title: displayName, major: 0, minor: 0, hasVersion: false, lineRank: 0)
            case .grok:
                return named(family.title, version: dottedAfter(hay, "grok"), rank: 0)
            case .composer:
                return named(family.title, version: dottedAfter(hay, "composer"), rank: 0)
            case .claude:
                return claudeLine(hay)
            case .gpt:
                if hay.contains("codex"), let version = dottedAfter(hay, "codex") {
                    return named("Codex", version: version, rank: 1)
                }
                return named("GPT", version: dottedAfter(hay, "gpt") ?? dottedAfter(hay, "codex"), rank: 0)
            case .gemini:
                return named("Gemini", version: dottedAfter(hay, "gemini"), rank: 0)
            case .kimi:
                return named("Kimi", version: dottedAfter(hay, "kimi"), rank: 0)
            case .glm:
                return named("GLM", version: dottedAfter(hay, "glm"), rank: 0)
            }
        }

        public static func sortNewestFirst(_ lhs: Line, _ rhs: Line) -> Bool {
            if lhs.lineRank != rhs.lineRank { return lhs.lineRank < rhs.lineRank }
            if lhs.hasVersion != rhs.hasVersion { return lhs.hasVersion && !rhs.hasVersion }
            if lhs.major != rhs.major { return lhs.major > rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor > rhs.minor }
            return lhs.title < rhs.title
        }
    }

    /// Newton group-header count: own text node so “Composer” + “5 models” never reads as “Composer 5”.
    public static func familyGroupCountLabel(_ count: Int) -> String {
        count == 1 ? "1 model" : "\(count) models"
    }

    public static func displayName(for modelIntent: String) -> String {
        let trimmed = modelIntent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown model" }
        let raw = known[trimmed] ?? humanize(trimmed)
        return applyFamilyDisplay(intent: trimmed, name: raw)
    }

    public static func humanize(_ modelIntent: String) -> String {
        let parts = modelIntent
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return modelIntent }
        return parts.map(titleCasePart).joined(separator: " ")
    }

    private static func applyFamilyDisplay(intent: String, name: String) -> String {
        switch Family.of(modelIntent: intent, displayName: name) {
        case .grok:
            let lower = name.lowercased()
            if lower.hasPrefix("cursor grok") { return name }
            if lower.hasPrefix("grok") { return "Cursor \(name)" }
            return "Cursor Grok \(name)"
        case .auto:
            return "Auto"
        case .composer, .claude, .gpt, .gemini, .kimi, .glm, .other:
            return name
        }
    }

    private static func spacedHay(_ intent: String, _ display: String) -> String {
        "\(intent) \(display)"
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private struct Dotted {
        var major: Int
        var minor: Int
        var hasMinor: Bool
        var formatted: String { hasMinor ? "\(major).\(minor)" : "\(major)" }
    }

    private static func dottedAfter(_ hay: String, _ token: String) -> Dotted? {
        let escaped = NSRegularExpression.escapedPattern(for: token)
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(escaped)\\s+(\\d+)(?:\\.(\\d+))?",
            options: []
        ) else {
            return nil
        }
        let range = NSRange(hay.startIndex..<hay.endIndex, in: hay)
        guard let match = regex.firstMatch(in: hay, options: [], range: range),
              let majorRange = Range(match.range(at: 1), in: hay),
              let major = Int(hay[majorRange])
        else {
            return nil
        }
        let minorRange = match.range(at: 2)
        if minorRange.location != NSNotFound, let range = Range(minorRange, in: hay) {
            return Dotted(major: major, minor: Int(hay[range]) ?? 0, hasMinor: true)
        }
        return Dotted(major: major, minor: 0, hasMinor: false)
    }

    private static func named(_ stem: String, version: Dotted?, rank: Int) -> Line {
        guard let version else {
            return Line(title: stem, major: 0, minor: 0, hasVersion: false, lineRank: rank)
        }
        return Line(
            title: "\(stem) \(version.formatted)",
            major: version.major,
            minor: version.minor,
            hasVersion: true,
            lineRank: rank
        )
    }

    private static func claudeLine(_ hay: String) -> Line {
        let lines: [(token: String, title: String, rank: Int)] = [
            ("sonnet", "Sonnet", 0),
            ("opus", "Opus", 1),
            ("fable", "Fable", 2),
            ("haiku", "Haiku", 3),
        ]
        for line in lines where hay.contains(line.token) {
            let version = dottedAfter(hay, line.token) ?? dottedAfter(hay, "claude")
            return named(line.title, version: version, rank: line.rank)
        }
        return named("Claude", version: dottedAfter(hay, "claude"), rank: 4)
    }

    private static func titleCasePart(_ part: String) -> String {
        let lower = part.lowercased()
        switch lower {
        case "gpt":
            return "GPT"
        case "claude":
            return "Claude"
        case "cursor":
            return "Cursor"
        case "composer":
            return "Composer"
        case "grok":
            return "Grok"
        case "codex":
            return "Codex"
        case "sonnet":
            return "Sonnet"
        case "opus":
            return "Opus"
        case "fable":
            return "Fable"
        case "gemini":
            return "Gemini"
        case "kimi":
            return "Kimi"
        case "glm":
            return "GLM"
        case "sol":
            return "Sol"
        case "xhigh":
            return "XHigh"
        case "thinking":
            return "Thinking"
        default:
            if lower.first?.isLetter == true {
                return part.prefix(1).uppercased() + part.dropFirst()
            }
            return part
        }
    }
}
