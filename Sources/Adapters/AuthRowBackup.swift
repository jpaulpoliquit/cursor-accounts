import CursorBarDomain
import Foundation

/// Prior presence/value for affected auth keys only. Never logs blob contents.
public enum AuthRowPresence: Sendable, Equatable, Codable {
    case absent
    case present(Data)

    private enum CodingKeys: String, CodingKey {
        case kind
        case blobBase64
    }

    private enum Kind: String, Codable {
        case absent
        case present
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .absent:
            self = .absent
        case .present:
            let encoded = try container.decode(String.self, forKey: .blobBase64)
            guard let data = Data(base64Encoded: encoded) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .blobBase64,
                    in: container,
                    debugDescription: "Invalid base64 auth row blob"
                )
            }
            self = .present(data)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .absent:
            try container.encode(Kind.absent, forKey: .kind)
        case .present(let data):
            try container.encode(Kind.present, forKey: .kind)
            try container.encode(data.base64EncodedString(), forKey: .blobBase64)
        }
    }
}

public struct AuthRowBackup: Sendable, Equatable, Codable {
    public let rows: [CursorAuthKey: AuthRowPresence]

    public init(rows: [CursorAuthKey: AuthRowPresence]) {
        self.rows = rows
    }

    public subscript(key: CursorAuthKey) -> AuthRowPresence? {
        rows[key]
    }

    private enum CodingKeys: String, CodingKey {
        case rows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: AuthRowPresence].self, forKey: .rows)
        var parsed: [CursorAuthKey: AuthRowPresence] = [:]
        for (key, presence) in raw {
            guard let authKey = CursorAuthKey(rawValue: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .rows,
                    in: container,
                    debugDescription: "Unknown auth key"
                )
            }
            parsed[authKey] = presence
        }
        self.rows = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var raw: [String: AuthRowPresence] = [:]
        for (key, presence) in rows {
            raw[key.rawValue] = presence
        }
        try container.encode(raw, forKey: .rows)
    }
}

extension AuthRowBackup: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        let parts = rows.keys.sorted { $0.rawValue < $1.rawValue }.map { key in
            switch rows[key] {
            case .absent:
                return "\(key.rawValue)=absent"
            case .present:
                return "\(key.rawValue)=present(<redacted>)"
            case .none:
                return "\(key.rawValue)=?"
            }
        }
        return "AuthRowBackup(\(parts.joined(separator: ", ")))"
    }

    public var debugDescription: String { description }
}

extension AuthRowPresence: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .absent: "absent"
        case .present: "present(<redacted>)"
        }
    }

    public var debugDescription: String { description }
}
