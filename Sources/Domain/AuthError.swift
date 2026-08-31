import Foundation

/// Auth-stage failures. Status and stage only; never response bodies or tokens.
public enum AuthError: Error, Sendable, Equatable {
    case http(stage: AuthStage, status: Int)
    case transport(stage: AuthStage)
    case malformed(stage: AuthStage)
    case denied(stage: AuthStage)
    case timedOut(stage: AuthStage)
    case cancelled(stage: AuthStage)
    case invalidAPIKey
    case missingCredentials
    case persistenceFailed
    case seatBusy
    case identityUnavailable
}

public enum AuthStage: String, Sendable, Equatable {
    case poll
    case refresh
    case exchange
    case login
    case signOut
    case identity
}

extension AuthError: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .http(let stage, let status):
            "AuthError.http(stage: \(stage.rawValue), status: \(status))"
        case .transport(let stage):
            "AuthError.transport(stage: \(stage.rawValue))"
        case .malformed(let stage):
            "AuthError.malformed(stage: \(stage.rawValue))"
        case .denied(let stage):
            "AuthError.denied(stage: \(stage.rawValue))"
        case .timedOut(let stage):
            "AuthError.timedOut(stage: \(stage.rawValue))"
        case .cancelled(let stage):
            "AuthError.cancelled(stage: \(stage.rawValue))"
        case .invalidAPIKey:
            "AuthError.invalidAPIKey"
        case .missingCredentials:
            "AuthError.missingCredentials"
        case .persistenceFailed:
            "AuthError.persistenceFailed"
        case .seatBusy:
            "AuthError.seatBusy"
        case .identityUnavailable:
            "AuthError.identityUnavailable"
        }
    }

    public var debugDescription: String { description }
}
