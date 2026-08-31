import Foundation

/// Non-empty trimmed email string. Construct only through the failable initializer.
public struct Email: Hashable, Codable, Sendable {
    public let value: String

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.value = trimmed
    }
}
