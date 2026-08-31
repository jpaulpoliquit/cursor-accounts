import Foundation

/// Opaque access token. Never interpolates into logs or debug output. Not Codable.
public struct AccessToken: Sendable, Equatable, Hashable {
    public let rawValue: String

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.rawValue = trimmed
    }
}

extension AccessToken: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "<AccessToken>" }
    public var debugDescription: String { "<AccessToken>" }
    public var customMirror: Mirror {
        Mirror(self, children: ["rawValue": "<redacted>"], displayStyle: .struct)
    }
}

/// Opaque refresh token. Never interpolates into logs or debug output. Not Codable.
public struct RefreshToken: Sendable, Equatable, Hashable {
    public let rawValue: String

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.rawValue = trimmed
    }
}

extension RefreshToken: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "<RefreshToken>" }
    public var debugDescription: String { "<RefreshToken>" }
    public var customMirror: Mirror {
        Mirror(self, children: ["rawValue": "<redacted>"], displayStyle: .struct)
    }
}

/// Opaque API key credential material. Never interpolates into logs or debug output. Not Codable.
public struct APIKey: Sendable, Equatable, Hashable {
    public let rawValue: String

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.rawValue = trimmed
    }
}

extension APIKey: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "<APIKey>" }
    public var debugDescription: String { "<APIKey>" }
    public var customMirror: Mirror {
        Mirror(self, children: ["rawValue": "<redacted>"], displayStyle: .struct)
    }
}
