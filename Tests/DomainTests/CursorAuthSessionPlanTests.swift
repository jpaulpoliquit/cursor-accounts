import CursorBarDomain
import XCTest

final class CursorAuthSessionPlanTests: XCTestCase {
    func testMembershipAuthIdDerivedFromJWTSubject() throws {
        let accessJWT = unsignedJWT(sub: "auth0|seat-a", exp: 1_900_000_000)
        let access = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: accessJWT))
        let refresh = try XCTUnwrap(RefreshToken(unsignedJWT(sub: "auth0|seat-a", exp: 1_900_000_000)))
        let material = CursorAuthSessionMaterial(
            access: access,
            refresh: refresh,
            email: Email("a@example.com"),
            displayName: DisplayName("Ada"),
            membershipType: "ultra",
            subscriptionStatus: "active"
        )

        let plan = try XCTUnwrap(success(CursorAuthSessionPlanBuilder.build(from: material)))
        XCTAssertEqual(plan.expectedSubject, "auth0|seat-a")
        XCTAssertEqual(plan.upserts[.stripeMembershipAuthId], "auth0|seat-a")
        XCTAssertEqual(plan.upserts[.accessToken], accessJWT)
        XCTAssertEqual(plan.upserts[.cachedEmail], "a@example.com")
        XCTAssertEqual(plan.upserts[.stripeMembershipType], "ultra")
        XCTAssertEqual(plan.upserts[.stripeSubscriptionStatus], "active")
        XCTAssertTrue(plan.upserts[.cachedScopedProfile]?.contains("Ada") == true)
        XCTAssertFalse(String(describing: plan).contains(accessJWT))
        XCTAssertFalse(String(reflecting: material).contains(accessJWT))
    }

    func testRejectsAPIKeyInRefreshSlotAndAccessConstruction() {
        XCTAssertNil(ConnectReadyAccessToken(validatedJWT: "crsr_live_secret"))
        XCTAssertNil(ConnectReadyAccessToken(AccessToken("crsr_live_secret")!))

        let access = try! XCTUnwrap(ConnectReadyAccessToken(validatedJWT: unsignedJWT(sub: "sub", exp: 1)))
        let refresh = try! XCTUnwrap(RefreshToken("crsr_refresh_secret"))
        let material = CursorAuthSessionMaterial(
            access: access,
            refresh: refresh,
            email: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )
        let result = CursorAuthSessionPlanBuilder.build(from: material)
        guard case .failure(.apiKeyInRefreshSlot) = result else {
            return XCTFail("expected apiKeyInRefreshSlot, got \(result)")
        }
    }

    func testRejectsSubjectMismatchAndMalformedSubject() {
        let accessJWT = unsignedJWT(sub: "auth0|real", exp: 1_900_000_000)
        let access = try! XCTUnwrap(ConnectReadyAccessToken(validatedJWT: accessJWT))
        let refresh = try! XCTUnwrap(RefreshToken(unsignedJWT(sub: "auth0|real", exp: 1_900_000_000)))

        let mismatch = CursorAuthSessionMaterial(
            access: access,
            refresh: refresh,
            email: Email("a@example.com"),
            membershipType: "pro",
            subscriptionStatus: "active",
            expectedSubject: "auth0|other"
        )
        guard case .failure(.subjectMismatch) = CursorAuthSessionPlanBuilder.build(from: mismatch) else {
            return XCTFail("expected subjectMismatch")
        }

        let badJWT = "not-a-jwt"
        let badAccess = try! XCTUnwrap(ConnectReadyAccessToken(validatedJWT: badJWT))
        let badMaterial = CursorAuthSessionMaterial(
            access: badAccess,
            refresh: refresh,
            email: nil,
            membershipType: nil,
            subscriptionStatus: nil
        )
        guard case .failure(.malformedJWTSubject) = CursorAuthSessionPlanBuilder.build(from: badMaterial) else {
            return XCTFail("expected malformedJWTSubject")
        }
    }

    func testKeyPolicyExhaustiveUpsertAndDeleteSets() throws {
        let access = try XCTUnwrap(
            ConnectReadyAccessToken(validatedJWT: unsignedJWT(sub: "sub-1", exp: 1_900_000_000))
        )
        let refresh = try XCTUnwrap(RefreshToken(unsignedJWT(sub: "sub-1", exp: 1_900_000_000)))

        let full = try XCTUnwrap(
            success(
                CursorAuthSessionPlanBuilder.build(
                    from: CursorAuthSessionMaterial(
                        access: access,
                        refresh: refresh,
                        email: Email("full@example.com"),
                        displayName: DisplayName("Full"),
                        membershipType: "ultra",
                        subscriptionStatus: "active"
                    )
                )
            )
        )
        XCTAssertEqual(
            Set(full.upserts.keys),
            [
                .accessToken,
                .refreshToken,
                .stripeMembershipAuthId,
                .cachedEmail,
                .cachedScopedProfile,
                .stripeMembershipType,
                .stripeSubscriptionStatus,
            ]
        )
        XCTAssertEqual(full.deletes, CursorAuthKey.alwaysDelete)

        let sparse = try XCTUnwrap(
            success(
                CursorAuthSessionPlanBuilder.build(
                    from: CursorAuthSessionMaterial(
                        access: access,
                        refresh: refresh,
                        email: nil,
                        membershipType: nil,
                        subscriptionStatus: nil
                    )
                )
            )
        )
        XCTAssertEqual(
            Set(sparse.upserts.keys),
            [.accessToken, .refreshToken, .stripeMembershipAuthId]
        )
        XCTAssertEqual(
            sparse.deletes,
            CursorAuthKey.alwaysDelete.union(CursorAuthKey.optionalAccountCache)
        )

        for key in CursorAuthKey.allCases {
            let policy = CursorAuthKeyPolicy.policy(for: key)
            switch key {
            case .accessToken, .refreshToken, .stripeMembershipAuthId:
                XCTAssertEqual(policy, .requiredUpsert)
            case .cachedEmail, .cachedScopedProfile, .stripeMembershipType, .stripeSubscriptionStatus:
                XCTAssertEqual(policy, .upsertOrDeleteToAvoidBleed)
            case .cachedTeam, .teamId, .stripeCustomerId:
                XCTAssertEqual(policy, .alwaysDelete)
            }
        }
        XCTAssertEqual(CursorAuthKey.affectedKeys, Set(CursorAuthKey.allCases))
    }

    func testBuildFromStoredSeatRecord() throws {
        let accessJWT = unsignedJWT(sub: "auth0|seat", exp: 1_900_000_000)
        let access = try XCTUnwrap(ConnectReadyAccessToken(validatedJWT: accessJWT))
        let refresh = try XCTUnwrap(RefreshToken(unsignedJWT(sub: "auth0|seat", exp: 1_900_000_000)))
        let record = StoredSeatRecord(
            seatID: .seat2,
            identity: .subject("auth0|seat"),
            access: access.asAccessToken,
            refresh: refresh,
            email: Email("seat@example.com"),
            displayName: DisplayName("Seat"),
            expiresAt: nil,
            membershipType: "pro",
            subscriptionStatus: "active"
        )
        let plan = try XCTUnwrap(success(CursorAuthSessionPlanBuilder.build(from: record, access: access, refresh: refresh)))
        XCTAssertEqual(plan.upserts[.stripeMembershipAuthId], "auth0|seat")
        XCTAssertEqual(plan.upserts[.cachedEmail], "seat@example.com")
    }

    private func success(
        _ result: Result<CursorAuthSessionPlan, CursorAuthSessionPlanError>
    ) -> CursorAuthSessionPlan? {
        switch result {
        case .success(let plan):
            return plan
        case .failure:
            return nil
        }
    }

    private func unsignedJWT(sub: String, exp: Int) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URL()
        let payload = Data(#"{"sub":"\#(sub)","exp":\#(exp)}"#.utf8).base64URL()
        return "\(header).\(payload).sig"
    }
}

private extension Data {
    func base64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
