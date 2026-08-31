import Foundation

/// Access material proven safe for Dashboard Connect. Raw `crsr_` keys cannot construct this type.
public struct ConnectReadyAccessToken: Sendable, Equatable, Hashable {
    public let rawValue: String

    public init?(_ access: AccessToken) {
        let raw = access.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        guard !raw.hasPrefix("crsr_") else { return nil }
        self.rawValue = raw
    }

    /// Test and AuthEngine entry for already-validated JWT material.
    public init?(validatedJWT raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("crsr_") else { return nil }
        self.rawValue = trimmed
    }

    public var asAccessToken: AccessToken {
        AccessToken(rawValue)!
    }
}

extension ConnectReadyAccessToken: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "<ConnectReadyAccessToken>" }
    public var debugDescription: String { "<ConnectReadyAccessToken>" }
    public var customMirror: Mirror {
        Mirror(self, children: ["rawValue": "<redacted>"], displayStyle: .struct)
    }
}
