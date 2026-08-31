import Foundation

/// Per-seat login presentation. No loading/error boolean soup.
public enum SeatLoginFailure: Sendable, Equatable, Hashable {
    case denied
    case timedOut
    case cancelled
    case duplicateIdentity
    case persistenceFailed
    case seatNotEmpty
    case malformed
    case identityUnavailable

    public var surfaceMessage: String {
        switch self {
        case .denied:
            return "Sign-in was denied"
        case .timedOut:
            return "Sign-in timed out"
        case .cancelled:
            return "Sign-in cancelled"
        case .duplicateIdentity:
            return "That account is already signed in"
        case .persistenceFailed:
            return "Could not save seat credentials"
        case .seatNotEmpty:
            return "Seat already has an account"
        case .malformed:
            return "Sign-in response was invalid"
        case .identityUnavailable:
            return "Could not finish sign-in. Try again."
        }
    }
}

public enum SeatLoginPhase: Sendable, Equatable, Hashable {
    case idle
    case openingBrowser
    case polling
    /// Poll tokens received; hydrating usable identity before Keychain bind.
    case finishingSignIn
    case failed(SeatLoginFailure)
    case succeeded(placedOn: SeatID)

    public var isInFlight: Bool {
        switch self {
        case .openingBrowser, .polling, .finishingSignIn:
            return true
        case .idle, .failed, .succeeded:
            return false
        }
    }

    public var failure: SeatLoginFailure? {
        if case .failed(let failure) = self {
            return failure
        }
        return nil
    }

    /// One current attempt. Success clears ghosts so Connect does not stay failed forever.
    public static func phases(after outcome: DeviceLoginOutcome, requested: SeatID) -> [SeatID: SeatLoginPhase] {
        switch outcome {
        case .signedIn:
            return [:]
        case .denied:
            return [requested: .failed(.denied)]
        case .timedOut:
            return [requested: .failed(.timedOut)]
        case .cancelled:
            return [requested: .failed(.cancelled)]
        case .malformedResponse:
            return [requested: .failed(.malformed)]
        case .persistenceFailed:
            return [requested: .failed(.persistenceFailed)]
        case .seatNotEmpty:
            return [requested: .failed(.seatNotEmpty)]
        case .identityUnavailable:
            return [requested: .failed(.identityUnavailable)]
        }
    }
}

public enum OnDemandAmountValidation: Sendable {
    public enum Rejection: Error, Sendable, Equatable {
        case notPositiveWholeDollars
        case belowPolicyMinimum(Int)
        case abovePolicyMaximum(Int)
    }

    public static func validate(
        wholeDollars: Int,
        policy: UsagePolicy?
    ) -> Result<PositiveDollars, Rejection> {
        guard let dollars = PositiveDollars(wholeDollars) else {
            return .failure(.notPositiveWholeDollars)
        }
        if let minCents = policy?.minLimitCents?.cents {
            let minDollars = Int((minCents + 99) / 100)
            if dollars.amount < minDollars {
                return .failure(.belowPolicyMinimum(minDollars))
            }
        }
        if let maxCents = policy?.maxLimitCents?.cents {
            let maxDollars = Int(maxCents / 100)
            if maxDollars > 0, dollars.amount > maxDollars {
                return .failure(.abovePolicyMaximum(maxDollars))
            }
        }
        return .success(dollars)
    }
}
