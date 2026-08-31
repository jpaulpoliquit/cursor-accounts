import Foundation

/// Human account name. Non-empty, trimmed, and never an email-shaped string.
public struct DisplayName: Hashable, Codable, Sendable {
    public let value: String

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains("@") else { return nil }
        self.value = trimmed
    }
}
