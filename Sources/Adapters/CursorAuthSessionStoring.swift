import CursorBarDomain
import Foundation

/// Row-level auth inject/restore for shared-profile switching.
public protocol CursorAuthSessionStoring: Sendable {
    /// Read exact prior presence/value for keys before mutation. Used for durable journaling.
    func readBackup(keys: Set<CursorAuthKey>) throws -> AuthRowBackup
    func inject(plan: CursorAuthSessionPlan) throws -> AuthRowBackup
    func restore(_ backup: AuthRowBackup) throws
    func readIdentity() throws -> CursorIDEIdentity?
}

extension CursorAuthSessionStore: CursorAuthSessionStoring {}
