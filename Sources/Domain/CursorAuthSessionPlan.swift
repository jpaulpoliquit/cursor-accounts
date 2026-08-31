import Foundation

/// Pure injection plan for shared-profile `cursorAuth/*` rows.
/// Built only from Domain session material. Never carries Adapter types.
public struct CursorAuthSessionPlan: Sendable, Equatable {
    public let upserts: [CursorAuthKey: String]
    public let deletes: Set<CursorAuthKey>
    public let expectedSubject: String

    public init(upserts: [CursorAuthKey: String], deletes: Set<CursorAuthKey>, expectedSubject: String) {
        self.upserts = upserts
        self.deletes = deletes
        self.expectedSubject = expectedSubject
    }

    public var affectedKeys: Set<CursorAuthKey> {
        Set(upserts.keys).union(deletes)
    }
}

public enum CursorAuthSessionPlanError: Error, Sendable, Equatable {
    case emptyAccessToken
    case emptyRefreshToken
    case apiKeyInAccessSlot
    case apiKeyInRefreshSlot
    case malformedJWTSubject
    case subjectMismatch
}

/// Connect-ready session material for plan construction. Tokens stay redacted in descriptions.
public struct CursorAuthSessionMaterial: Sendable, Equatable {
    public let access: ConnectReadyAccessToken
    public let refresh: RefreshToken
    public let email: Email?
    public let displayName: DisplayName?
    public let membershipType: String?
    public let subscriptionStatus: String?
    public let scopedProfileJSON: String?
    /// When set, must equal the access JWT `sub`.
    public let expectedSubject: String?

    public init(
        access: ConnectReadyAccessToken,
        refresh: RefreshToken,
        email: Email?,
        displayName: DisplayName? = nil,
        membershipType: String?,
        subscriptionStatus: String?,
        scopedProfileJSON: String? = nil,
        expectedSubject: String? = nil
    ) {
        self.access = access
        self.refresh = refresh
        self.email = email
        self.displayName = displayName
        self.membershipType = membershipType
        self.subscriptionStatus = subscriptionStatus
        self.scopedProfileJSON = scopedProfileJSON
            ?? Self.scopedProfileJSON(displayName: displayName)
        self.expectedSubject = expectedSubject
    }

    public init(record: StoredSeatRecord, access: ConnectReadyAccessToken, refresh: RefreshToken) {
        let subject: String?
        if case .subject(let value) = record.identity {
            subject = value
        } else {
            subject = nil
        }
        self.init(
            access: access,
            refresh: refresh,
            email: record.email,
            displayName: record.displayName,
            membershipType: record.membershipType,
            subscriptionStatus: record.subscriptionStatus,
            scopedProfileJSON: Self.scopedProfileJSON(displayName: record.displayName),
            expectedSubject: subject
        )
    }

    public static func scopedProfileJSON(displayName: DisplayName?) -> String? {
        guard let displayName else { return nil }
        let object: [String: String] = ["displayName": displayName.value]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return text
    }
}

public enum CursorAuthSessionPlanBuilder {
    public static func build(from material: CursorAuthSessionMaterial) -> Result<CursorAuthSessionPlan, CursorAuthSessionPlanError> {
        let accessRaw = material.access.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshRaw = material.refresh.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !accessRaw.isEmpty else { return .failure(.emptyAccessToken) }
        guard !refreshRaw.isEmpty else { return .failure(.emptyRefreshToken) }
        if accessRaw.hasPrefix("crsr_") { return .failure(.apiKeyInAccessSlot) }
        if refreshRaw.hasPrefix("crsr_") { return .failure(.apiKeyInRefreshSlot) }

        guard let claims = JWTClaims.decode(jwt: accessRaw),
              let subject = normalizedSubject(claims.subject)
        else {
            return .failure(.malformedJWTSubject)
        }

        if let expected = material.expectedSubject {
            guard let normalizedExpected = normalizedSubject(expected) else {
                return .failure(.malformedJWTSubject)
            }
            guard normalizedExpected == subject else {
                return .failure(.subjectMismatch)
            }
        }

        var upserts: [CursorAuthKey: String] = [
            .accessToken: accessRaw,
            .refreshToken: refreshRaw,
            .stripeMembershipAuthId: subject,
        ]
        var deletes = CursorAuthKey.alwaysDelete

        applyOptional(
            key: .cachedEmail,
            value: material.email?.value,
            upserts: &upserts,
            deletes: &deletes
        )
        applyOptional(
            key: .cachedScopedProfile,
            value: trimmedNonEmpty(material.scopedProfileJSON),
            upserts: &upserts,
            deletes: &deletes
        )
        applyOptional(
            key: .stripeMembershipType,
            value: trimmedNonEmpty(material.membershipType),
            upserts: &upserts,
            deletes: &deletes
        )
        applyOptional(
            key: .stripeSubscriptionStatus,
            value: trimmedNonEmpty(material.subscriptionStatus),
            upserts: &upserts,
            deletes: &deletes
        )

        return .success(
            CursorAuthSessionPlan(
                upserts: upserts,
                deletes: deletes,
                expectedSubject: subject
            )
        )
    }

    public static func build(
        from record: StoredSeatRecord,
        access: ConnectReadyAccessToken,
        refresh: RefreshToken
    ) -> Result<CursorAuthSessionPlan, CursorAuthSessionPlanError> {
        build(from: CursorAuthSessionMaterial(record: record, access: access, refresh: refresh))
    }

    private static func applyOptional(
        key: CursorAuthKey,
        value: String?,
        upserts: inout [CursorAuthKey: String],
        deletes: inout Set<CursorAuthKey>
    ) {
        if let value {
            upserts[key] = value
            deletes.remove(key)
        } else {
            deletes.insert(key)
            upserts.removeValue(forKey: key)
        }
    }

    private static func normalizedSubject(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func trimmedNonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension CursorAuthSessionPlan: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        let upsertKeys = upserts.keys.map(\.rawValue).sorted().joined(separator: ",")
        let deleteKeys = deletes.map(\.rawValue).sorted().joined(separator: ",")
        return "CursorAuthSessionPlan(upserts:[\(upsertKeys)], deletes:[\(deleteKeys)], subject:<redacted>)"
    }

    public var debugDescription: String { description }
}

extension CursorAuthSessionMaterial: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "CursorAuthSessionMaterial(email: \(email?.value ?? "nil"), membership: \(membershipType ?? "nil"))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "access": "<redacted>",
                "refresh": "<redacted>",
                "email": email?.value ?? "nil",
                "displayName": displayName?.value ?? "nil",
                "membershipType": membershipType ?? "nil",
                "subscriptionStatus": subscriptionStatus ?? "nil",
                "scopedProfileJSON": scopedProfileJSON == nil ? "nil" : "<redacted>",
                "expectedSubject": expectedSubject == nil ? "nil" : "<redacted>",
            ],
            displayStyle: .struct
        )
    }
}

extension CursorAuthSessionPlanError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .emptyAccessToken: "CursorAuthSessionPlanError.emptyAccessToken"
        case .emptyRefreshToken: "CursorAuthSessionPlanError.emptyRefreshToken"
        case .apiKeyInAccessSlot: "CursorAuthSessionPlanError.apiKeyInAccessSlot"
        case .apiKeyInRefreshSlot: "CursorAuthSessionPlanError.apiKeyInRefreshSlot"
        case .malformedJWTSubject: "CursorAuthSessionPlanError.malformedJWTSubject"
        case .subjectMismatch: "CursorAuthSessionPlanError.subjectMismatch"
        }
    }
}
