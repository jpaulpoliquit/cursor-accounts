import CursorBarDomain
import Foundation

/// Session-JWT → usable email/displayName. Login must not Keychain-bind without this.
public protocol AccountIdentityHydrating: Sendable {
    func fetchIdentity(access: ConnectReadyAccessToken) async throws -> HydratedAccountIdentity
}

public struct DashboardAccountIdentityHydrator: AccountIdentityHydrating {
    private let client: DashboardClient

    public init(client: DashboardClient = DashboardClient()) {
        self.client = client
    }

    public func fetchIdentity(access: ConnectReadyAccessToken) async throws -> HydratedAccountIdentity {
        try await client.getMe(access: access)
    }
}

/// Classifies GetMe failures for bounded login retry without deleting valid poll tokens prematurely.
public enum IdentityHydrationFailure: Error, Sendable, Equatable {
    case transient
    case permanent
    case cancelled

    public static func classify(_ error: DashboardClient.ClientError) -> IdentityHydrationFailure {
        switch error {
        case .transport(.cancelled):
            return .cancelled
        case .transport(.httpStatus(let code)):
            if code == 401 || code == 403 || (400..<500).contains(code) {
                return .permanent
            }
            return .transient
        case .transport(.transport), .transport(.rawAPIKeyCredential):
            return .transient
        case .decode, .invalidHardLimit:
            return .permanent
        }
    }
}
