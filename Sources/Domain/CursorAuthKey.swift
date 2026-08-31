import Foundation

/// Scoped `ItemTable` keys owned by Cursor account-session switching.
/// Every case is either upserted, deleted, or classified as out-of-scope.
public enum CursorAuthKey: String, CaseIterable, Sendable, Hashable, Codable {
    case accessToken = "cursorAuth/accessToken"
    case refreshToken = "cursorAuth/refreshToken"
    case cachedEmail = "cursorAuth/cachedEmail"
    case cachedScopedProfile = "cursorAuth/cachedScopedProfile"
    case stripeMembershipType = "cursorAuth/stripeMembershipType"
    case stripeSubscriptionStatus = "cursorAuth/stripeSubscriptionStatus"
    case stripeMembershipAuthId = "cursorAuth/stripeMembershipAuthId"
    case cachedTeam = "cursorAuth/cachedTeam"
    case teamId = "cursorAuth/teamId"
    case stripeCustomerId = "cursorAuth/stripeCustomerId"

    /// Always written from Connect-ready session material.
    public static let requiredUpserts: Set<CursorAuthKey> = [
        .accessToken,
        .refreshToken,
        .stripeMembershipAuthId,
    ]

    /// Account-specific cache. Absent seat data deletes the prior row to prevent bleed.
    public static let optionalAccountCache: Set<CursorAuthKey> = [
        .cachedEmail,
        .cachedScopedProfile,
        .stripeMembershipType,
        .stripeSubscriptionStatus,
    ]

    /// Seat material cannot safely supply these. Always delete if present.
    public static let alwaysDelete: Set<CursorAuthKey> = [
        .cachedTeam,
        .teamId,
        .stripeCustomerId,
    ]

    /// Every key this switcher may read, upsert, or delete.
    public static let affectedKeys: Set<CursorAuthKey> = Set(CursorAuthKey.allCases)

    public var itemTableKey: String { rawValue }
}

/// Explicit omission policy for auth rows. Documented for tests and reviewers.
public enum CursorAuthKeyPolicy: Sendable, Equatable {
    /// Required session material. Missing/empty values reject the plan.
    case requiredUpsert
    /// Upsert when seat material provides a value; otherwise delete stale cache.
    case upsertOrDeleteToAvoidBleed
    /// Always delete. Seat data cannot reconstruct a safe value.
    case alwaysDelete
    /// Never touched by account switch (onboarding, BYOK, MCP secrets, unrelated rows).
    case preserveOutsideSwitcher

    public static func policy(for key: CursorAuthKey) -> CursorAuthKeyPolicy {
        if CursorAuthKey.requiredUpserts.contains(key) {
            return .requiredUpsert
        }
        if CursorAuthKey.optionalAccountCache.contains(key) {
            return .upsertOrDeleteToAvoidBleed
        }
        if CursorAuthKey.alwaysDelete.contains(key) {
            return .alwaysDelete
        }
        return .preserveOutsideSwitcher
    }
}
