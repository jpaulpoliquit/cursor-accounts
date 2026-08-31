import Foundation

/// Stable seat-binding key. Prefers JWT `sub`; falls back to email.
public enum SessionIdentity: Hashable, Sendable, Codable, Equatable {
    case subject(String)
    case email(Email)

    public static func resolve(subject: String?, email: Email?) -> SessionIdentity? {
        if let subject {
            let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return .subject(trimmed)
            }
        }
        if let email {
            return .email(email)
        }
        return nil
    }
}

extension SessionIdentity: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .subject: "<SessionIdentity.subject>"
        case .email(let email): "<SessionIdentity.email \(email.value)>"
        }
    }

    public var debugDescription: String { description }
}
