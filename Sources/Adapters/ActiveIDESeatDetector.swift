import CursorBarDomain
import Foundation

/// Resolves which seat matches the shared Cursor session identity.
/// Path, argv, and sidecar are never authoritative.
public struct ActiveIDESeatDetector: Sendable {
    private let identityReader: @Sendable () throws -> CursorIDEIdentity?
    private let rosterLoader: @Sendable () throws -> [StoredSeatRecord]

    public init(
        identityReader: @escaping @Sendable () throws -> CursorIDEIdentity?,
        rosterLoader: @escaping @Sendable () throws -> [StoredSeatRecord]
    ) {
        self.identityReader = identityReader
        self.rosterLoader = rosterLoader
    }

    /// Production detector: shared-profile DB identity vs Keychain roster.
    public init(
        sharedProfile: SharedCursorProfile? = nil,
        credentialStore: any SeatCredentialStore,
        homeDirectory: URL? = nil
    ) {
        let home = homeDirectory ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let profile = sharedProfile ?? SharedCursorProfile.default(homeDirectory: home)
        self.identityReader = {
            let store = CursorAuthSessionStore.forSharedProfile(
                profile,
                exitGuard: FixedCursorExitGuard(isCursorRunning: false)
            )
            return try store.readIdentity()
        }
        self.rosterLoader = {
            try credentialStore.loadAll()
        }
    }

    public func detect() -> SeatID? {
        let identity: CursorIDEIdentity
        do {
            guard let observed = try identityReader() else { return nil }
            identity = observed
        } catch {
            return nil
        }
        let roster: [StoredSeatRecord]
        do {
            roster = try rosterLoader()
        } catch {
            return nil
        }
        return CursorIDEIdentityMatcher.matchingSeat(identity: identity, roster: roster)
    }

    public func sharedProfileRoot(homeDirectory: URL) -> URL {
        SharedCursorProfile.default(homeDirectory: homeDirectory).rootDirectory
    }
}
