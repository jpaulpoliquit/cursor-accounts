import CursorBarDomain
import Foundation

/// Per-seat auth owner. Login polling, identity hydration, refresh/exchange single-flight, local sign-out.
public actor AuthEngine {
    private let http: AuthHTTPClient
    private let store: any SeatCredentialStore
    private let clock: any AuthClock
    private let sleeper: any AuthSleeper
    private let entropy: any AuthEntropy
    private let browser: any BrowserPresenting
    private let identityHydrator: any AccountIdentityHydrating

    private var loginTasks: [SeatID: Task<DeviceLoginOutcome, Never>] = [:]
    private var refreshTasks: [SeatID: Task<AuthHTTPClient.SessionTokens, Error>] = [:]
    private var exchangeTasks: [SeatID: Task<AuthHTTPClient.SessionTokens, Error>] = [:]

    public init(
        http: AuthHTTPClient = AuthHTTPClient(),
        store: any SeatCredentialStore = SeatKeychainStore(),
        clock: any AuthClock = SystemAuthClock(),
        sleeper: any AuthSleeper = SystemAuthSleeper(),
        entropy: any AuthEntropy = SystemAuthEntropy(),
        browser: any BrowserPresenting = NullBrowserPresenter(),
        identityHydrator: any AccountIdentityHydrating = DashboardAccountIdentityHydrator()
    ) {
        self.http = http
        self.store = store
        self.clock = clock
        self.sleeper = sleeper
        self.entropy = entropy
        self.browser = browser
        self.identityHydrator = identityHydrator
    }

    /// Next Keychain-empty seat. Preferred if empty; otherwise the next unused `seatN`.
    /// A seat whose record cannot be read counts as occupied so Connect never retries it.
    public func resolvedEmptySeat(preferred: SeatID) -> SeatID {
        SeatID.firstEmpty(preferred: preferred) { seatID in
            do {
                return try store.load(seatID: seatID) != nil
            } catch {
                return true
            }
        }
    }

    /// Starts empty-seat CLI-parity login. Does not claim `cursor://`. Browser presentation is App-owned.
    public func beginEmptySeatLogin(
        seatID: SeatID,
        onProgress: DeviceLoginProgressHandler? = nil
    ) async -> (DeviceLoginPresentation?, Task<DeviceLoginOutcome, Never>) {
        if let existing = loginTasks[seatID] {
            return (nil, existing)
        }

        do {
            if try store.load(seatID: seatID) != nil {
                let done = Task<DeviceLoginOutcome, Never> { .seatNotEmpty }
                return (nil, done)
            }
        } catch {
            let done = Task<DeviceLoginOutcome, Never> { .seatNotEmpty }
            return (nil, done)
        }

        let pair = PKCE.makePair(entropy: entropy)
        let uuid = entropy.randomUUID()
        let loginURL = PKCE.deepControlLoginURL(challenge: pair.challenge, uuid: uuid)
        let presentation = DeviceLoginPresentation(seatID: seatID, loginURL: loginURL)

        let task = Task<DeviceLoginOutcome, Never> { [http, sleeper, store, browser, identityHydrator] in
            do {
                try await browser.present(loginURL: loginURL)
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .cancelled
            }
            return await DeviceLoginRunner.pollUntilSettled(
                seatID: seatID,
                uuid: uuid,
                verifier: pair.verifier,
                http: http,
                sleeper: sleeper,
                store: store,
                identityHydrator: identityHydrator,
                onProgress: onProgress
            )
        }
        loginTasks[seatID] = task
        Task { [weak self] in
            _ = await task.value
            await self?.clearLoginTask(seatID)
        }
        return (presentation, task)
    }

    public func cancelLogin(seatID: SeatID) {
        loginTasks[seatID]?.cancel()
        loginTasks[seatID] = nil
    }

    /// Deletes only `app.cursorbar` seat credentials. Never touches Cursor Keychain/state.vscdb/revoke.
    public func signOutLocally(seatID: SeatID) throws {
        cancelLogin(seatID: seatID)
        refreshTasks[seatID]?.cancel()
        refreshTasks[seatID] = nil
        exchangeTasks[seatID]?.cancel()
        exchangeTasks[seatID] = nil
        try store.delete(seatID: seatID)
    }

    /// Stores optional long-lived `crsr_` key and exchanges for session JWTs on an empty or matching seat.
    public func bindAPIKey(seatID: SeatID, rawKey: String) async throws -> SeatID {
        guard rawKey.hasPrefix("crsr_"), let apiKey = APIKey(rawKey) else {
            throw AuthError.invalidAPIKey
        }
        let tokens = try await exchangeSingleFlight(seatID: seatID, apiKey: apiKey)
        guard let ready = ConnectReadyAccessToken(tokens.access) else {
            throw AuthError.malformed(stage: .exchange)
        }
        let hydration = await DeviceLoginRunner.hydrateIdentity(
            access: ready,
            sleeper: sleeper,
            identityHydrator: identityHydrator
        )
        switch hydration {
        case .cancelled:
            throw AuthError.cancelled(stage: .identity)
        case .failed:
            throw AuthError.identityUnavailable
        case .ready(let profile):
            if let existing = try store.load(seatID: seatID) {
                let claims = JWTClaims.decode(jwt: tokens.access.rawValue)
                guard let identity = SessionIdentity.resolve(subject: claims?.subject, email: profile.email) else {
                    throw AuthError.malformed(stage: .exchange)
                }
                if existing.identity != identity {
                    throw AuthError.seatBusy
                }
            }
            return try SeatCredentialBinder.placeTokens(
                preferredSeat: seatID,
                tokens: tokens,
                profile: profile,
                apiKey: apiKey,
                store: store
            )
        }
    }

    /// Dashboard-ready access. Refreshes or re-exchanges near JWT exp. Never returns raw `crsr_`.
    public func connectAccess(for seatID: SeatID) async throws -> ConnectReadyAccessToken {
        guard let record = try store.load(seatID: seatID) else {
            throw AuthError.missingCredentials
        }
        let now = clock.now()
        if let apiKey = record.apiKey {
            if needsRefresh(expiresAt: record.expiresAt, now: now) {
                let tokens = try await exchangeSingleFlight(seatID: seatID, apiKey: apiKey)
                try updateStoredTokens(seatID: seatID, tokens: tokens, preserving: record)
            }
            let fresh = try store.load(seatID: seatID) ?? record
            guard let ready = ConnectReadyAccessToken(fresh.access) else {
                throw AuthError.malformed(stage: .exchange)
            }
            return ready
        }
        if needsRefresh(expiresAt: record.expiresAt, now: now) {
            let tokens = try await refreshSingleFlight(seatID: seatID, refresh: record.refresh)
            try updateStoredTokens(seatID: seatID, tokens: tokens, preserving: record)
        }
        let fresh = try store.load(seatID: seatID) ?? record
        guard let ready = ConnectReadyAccessToken(fresh.access) else {
            throw AuthError.malformed(stage: .refresh)
        }
        return ready
    }

    /// One refresh then one replay for session credentials only (not API-key seats).
    public func withSessionConnectAccess<T: Sendable>(
        seatID: SeatID,
        operation: @Sendable (ConnectReadyAccessToken) async throws -> T
    ) async throws -> T {
        guard let record = try store.load(seatID: seatID) else {
            throw AuthError.missingCredentials
        }
        if record.apiKey != nil {
            let access = try await connectAccess(for: seatID)
            return try await operation(access)
        }
        let access = try await connectAccess(for: seatID)
        do {
            return try await operation(access)
        } catch let error as DashboardClient.ClientError {
            guard case .transport(.httpStatus(401)) = error else { throw error }
            let tokens = try await refreshSingleFlight(seatID: seatID, refresh: record.refresh)
            try updateStoredTokens(seatID: seatID, tokens: tokens, preserving: record)
            guard let ready = ConnectReadyAccessToken(tokens.access) else {
                throw AuthError.malformed(stage: .refresh)
            }
            return try await operation(ready)
        }
    }

    private func clearLoginTask(_ seatID: SeatID) {
        loginTasks[seatID] = nil
    }

    private func needsRefresh(expiresAt: Date?, now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt.addingTimeInterval(-AuthClientConstants.accessTokenRefreshSkew)
    }

    private func refreshSingleFlight(seatID: SeatID, refresh: RefreshToken) async throws -> AuthHTTPClient.SessionTokens {
        if let existing = refreshTasks[seatID] {
            return try await existing.value
        }
        let task = Task {
            try await http.refresh(refresh: refresh)
        }
        refreshTasks[seatID] = task
        defer { refreshTasks[seatID] = nil }
        return try await task.value
    }

    private func exchangeSingleFlight(seatID: SeatID, apiKey: APIKey) async throws -> AuthHTTPClient.SessionTokens {
        if let existing = exchangeTasks[seatID] {
            return try await existing.value
        }
        let task = Task {
            try await http.exchangeAPIKey(apiKey)
        }
        exchangeTasks[seatID] = task
        defer { exchangeTasks[seatID] = nil }
        return try await task.value
    }

    private func updateStoredTokens(
        seatID: SeatID,
        tokens: AuthHTTPClient.SessionTokens,
        preserving record: StoredSeatRecord
    ) throws {
        let claims = JWTClaims.decode(jwt: tokens.access.rawValue)
        let updated = StoredSeatRecord(
            seatID: seatID,
            identity: record.identity,
            access: tokens.access,
            refresh: tokens.refresh,
            email: record.email,
            displayName: record.displayName,
            pictureURL: claims?.pictureURL ?? record.pictureURL,
            expiresAt: claims?.expiresAt ?? record.expiresAt,
            membershipType: record.membershipType,
            subscriptionStatus: record.subscriptionStatus,
            apiKey: record.apiKey
        )
        try store.save(updated)
    }
}
