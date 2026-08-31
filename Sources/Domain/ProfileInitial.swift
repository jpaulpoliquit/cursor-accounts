import Foundation

/// One letter for an avatar when there is no photo.
public enum ProfileInitial {
    public static func letter(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source: String
        if let at = trimmed.firstIndex(of: "@") {
            source = String(trimmed[..<at])
        } else {
            source = trimmed
        }
        if let letter = source.first(where: \.isLetter) {
            return String(letter).uppercased()
        }
        return "?"
    }
}
