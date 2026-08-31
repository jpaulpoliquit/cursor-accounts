import CursorBarDomain
import Foundation

/// Builds a Connect-ready injection plan without touching Cursor's DB.
public protocol AccountSwitchSessionPreparing: Sendable {
    func preparePlan(for seatID: SeatID) async -> Result<CursorAuthSessionPlan, AccountSwitchPreflightReason>
}

/// AuthEngine + CursorBar Keychain backed preparer. Never writes Cursor-owned Keychain.
public struct AuthEngineSessionPreparer: AccountSwitchSessionPreparing {
    private let auth: AuthEngine
    private let store: any SeatCredentialStore

    public init(auth: AuthEngine, store: any SeatCredentialStore) {
        self.auth = auth
        self.store = store
    }

    public func preparePlan(
        for seatID: SeatID
    ) async -> Result<CursorAuthSessionPlan, AccountSwitchPreflightReason> {
        let initial: StoredSeatRecord
        do {
            guard let loaded = try store.load(seatID: seatID) else {
                return .failure(.missingCredentials)
            }
            initial = loaded
        } catch {
            return .failure(.missingCredentials)
        }

        guard initial.hasUsablePresentationIdentity else {
            return .failure(.identityNotHydrated)
        }

        let ready: ConnectReadyAccessToken
        do {
            ready = try await auth.connectAccess(for: seatID)
        } catch let error as AuthError {
            return .failure(Self.mapAuthError(error, hadAPIKey: initial.apiKey != nil))
        } catch {
            return .failure(initial.apiKey == nil ? .refreshFailed : .apiKeyExchangeFailed)
        }

        let record: StoredSeatRecord
        do {
            record = try store.load(seatID: seatID) ?? initial
        } catch {
            return .failure(.missingCredentials)
        }

        switch CursorAuthSessionPlanBuilder.build(from: record, access: ready, refresh: record.refresh) {
        case .success(let plan):
            return .success(plan)
        case .failure(.apiKeyInAccessSlot), .failure(.apiKeyInRefreshSlot), .failure(.malformedJWTSubject),
            .failure(.emptyAccessToken), .failure(.emptyRefreshToken):
            return .failure(.malformedSessionTokens)
        case .failure(.subjectMismatch):
            return .failure(.planRejected)
        }
    }

    private static func mapAuthError(_ error: AuthError, hadAPIKey: Bool) -> AccountSwitchPreflightReason {
        switch error {
        case .missingCredentials:
            return .missingCredentials
        case .identityUnavailable:
            return .identityNotHydrated
        case .malformed:
            return .malformedSessionTokens
        case .invalidAPIKey, .seatBusy:
            return hadAPIKey ? .apiKeyExchangeFailed : .refreshFailed
        case .http, .transport, .denied, .timedOut, .cancelled, .persistenceFailed:
            return hadAPIKey ? .apiKeyExchangeFailed : .refreshFailed
        }
    }
}

/// Deterministic preparer for engine tests. Never opens Keychain or network.
public struct FixedAccountSwitchSessionPreparer: AccountSwitchSessionPreparing {
    private let result: Result<CursorAuthSessionPlan, AccountSwitchPreflightReason>

    public init(result: Result<CursorAuthSessionPlan, AccountSwitchPreflightReason>) {
        self.result = result
    }

    public func preparePlan(
        for seatID: SeatID
    ) async -> Result<CursorAuthSessionPlan, AccountSwitchPreflightReason> {
        _ = seatID
        return result
    }
}
