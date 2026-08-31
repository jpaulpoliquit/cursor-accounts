import CursorBarDomain
import Foundation

/// Poll → hydrate → bind. Never Keychain-persists subject-only connected seats.
enum DeviceLoginRunner {
    static func pollUntilSettled(
        seatID: SeatID,
        uuid: UUID,
        verifier: String,
        http: AuthHTTPClient,
        sleeper: any AuthSleeper,
        store: any SeatCredentialStore,
        identityHydrator: any AccountIdentityHydrating,
        onProgress: DeviceLoginProgressHandler?
    ) async -> DeviceLoginOutcome {
        var transientFailures = 0
        for attempt in 0..<AuthClientConstants.pollMaxAttempts {
            if Task.isCancelled { return .cancelled }
            onProgress?(.polling)
            let result = await http.poll(uuid: uuid, verifier: verifier)
            switch result {
            case .pending:
                transientFailures = 0
                let delay = AuthClientConstants.pollDelayMs(attemptIndex: attempt)
                do {
                    try await sleeper.sleep(milliseconds: delay)
                } catch {
                    return .cancelled
                }
            case .tokens(let tokens):
                return await finishWithIdentity(
                    preferredSeat: seatID,
                    tokens: tokens,
                    apiKey: nil,
                    store: store,
                    sleeper: sleeper,
                    identityHydrator: identityHydrator,
                    onProgress: onProgress
                )
            case .denied:
                return .denied
            case .malformed:
                return .malformedResponse
            case .cancelled:
                return .cancelled
            case .httpStatus, .transport:
                transientFailures += 1
                if transientFailures >= AuthClientConstants.pollTransientFailureLimit {
                    return .timedOut
                }
                let delay = AuthClientConstants.pollDelayMs(attemptIndex: attempt)
                do {
                    try await sleeper.sleep(milliseconds: delay)
                } catch {
                    return .cancelled
                }
            }
        }
        return .timedOut
    }

    static func finishWithIdentity(
        preferredSeat: SeatID,
        tokens: AuthHTTPClient.SessionTokens,
        apiKey: APIKey?,
        store: any SeatCredentialStore,
        sleeper: any AuthSleeper,
        identityHydrator: any AccountIdentityHydrating,
        onProgress: DeviceLoginProgressHandler?
    ) async -> DeviceLoginOutcome {
        guard let ready = ConnectReadyAccessToken(tokens.access) else {
            return .malformedResponse
        }
        onProgress?(.finishingSignIn)
        switch await hydrateIdentity(
            access: ready,
            sleeper: sleeper,
            identityHydrator: identityHydrator
        ) {
        case .cancelled:
            return .cancelled
        case .failed:
            return .identityUnavailable
        case .ready(let profile):
            do {
                let placed = try SeatCredentialBinder.placeTokens(
                    preferredSeat: preferredSeat,
                    tokens: tokens,
                    profile: profile,
                    apiKey: apiKey,
                    store: store
                )
                return .signedIn(placedOn: placed)
            } catch let error as AuthError {
                switch error {
                case .identityUnavailable:
                    return .identityUnavailable
                case .seatBusy:
                    return .seatNotEmpty
                default:
                    return .persistenceFailed
                }
            } catch {
                return .persistenceFailed
            }
        }
    }

    enum HydrationOutcome: Sendable {
        case ready(HydratedAccountIdentity)
        case failed
        case cancelled
    }

    static func hydrateIdentity(
        access: ConnectReadyAccessToken,
        sleeper: any AuthSleeper,
        identityHydrator: any AccountIdentityHydrating
    ) async -> HydrationOutcome {
        for attempt in 0..<AuthClientConstants.identityHydrationMaxAttempts {
            if Task.isCancelled { return .cancelled }
            do {
                let profile = try await identityHydrator.fetchIdentity(access: access)
                guard profile.isUsableForPresentation else { return .failed }
                return .ready(profile)
            } catch let error as DashboardClient.ClientError {
                switch IdentityHydrationFailure.classify(error) {
                case .cancelled:
                    return .cancelled
                case .permanent:
                    return .failed
                case .transient:
                    let delay = AuthClientConstants.identityHydrationDelayMs(attemptIndex: attempt)
                    do {
                        try await sleeper.sleep(milliseconds: delay)
                    } catch {
                        return .cancelled
                    }
                }
            } catch is CancellationError {
                return .cancelled
            } catch {
                let delay = AuthClientConstants.identityHydrationDelayMs(attemptIndex: attempt)
                do {
                    try await sleeper.sleep(milliseconds: delay)
                } catch {
                    return .cancelled
                }
            }
        }
        return .failed
    }
}
