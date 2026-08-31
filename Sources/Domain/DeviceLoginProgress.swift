import Foundation

/// Login pipeline progress for UI. Distinct from final DeviceLoginOutcome.
public enum DeviceLoginProgress: Sendable, Equatable {
    case polling
    case finishingSignIn
}

public typealias DeviceLoginProgressHandler = @Sendable (DeviceLoginProgress) -> Void
