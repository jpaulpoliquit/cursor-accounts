import Foundation

/// Explicit display names for known modelIntent slugs, plus a robust humanized fallback.
public enum ModelDisplayNames {
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
        "default": "Default",
    ]

    public static func displayName(for modelIntent: String) -> String {
        let trimmed = modelIntent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown model" }
        if let mapped = known[trimmed] {
            return mapped
        }
        return humanize(trimmed)
    }

    public static func humanize(_ modelIntent: String) -> String {
        let parts = modelIntent
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return modelIntent }
        return parts.map(titleCasePart).joined(separator: " ")
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
