import Foundation

/// Outcome of an empty-seat CLI-parity device login. No bool soup.
public enum DeviceLoginOutcome: Sendable, Equatable {
    case signedIn(placedOn: SeatID)
    case denied
    case timedOut
    case cancelled
    case malformedResponse
    case persistenceFailed
    case seatNotEmpty
    /// Poll succeeded but identity hydration failed permanently / exhausted retries.
    /// Valid tokens were never persisted as a connected seat.
    case identityUnavailable
}

/// Presentation payload for App-owned browser seam. Sensitive URL; never log at info.
public struct DeviceLoginPresentation: Sendable, Equatable {
    public let seatID: SeatID
    public let loginURL: URL

    public init(seatID: SeatID, loginURL: URL) {
        self.seatID = seatID
        self.loginURL = loginURL
    }
}

extension DeviceLoginOutcome: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .signedIn(let seat): "DeviceLoginOutcome.signedIn(\(seat.rawValue))"
        case .denied: "DeviceLoginOutcome.denied"
        case .timedOut: "DeviceLoginOutcome.timedOut"
        case .cancelled: "DeviceLoginOutcome.cancelled"
        case .malformedResponse: "DeviceLoginOutcome.malformedResponse"
        case .persistenceFailed: "DeviceLoginOutcome.persistenceFailed"
        case .seatNotEmpty: "DeviceLoginOutcome.seatNotEmpty"
        case .identityUnavailable: "DeviceLoginOutcome.identityUnavailable"
        }
    }

    public var debugDescription: String { description }
}
