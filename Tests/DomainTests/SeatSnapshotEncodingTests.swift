import CursorBarDomain
import XCTest

final class SeatSnapshotEncodingTests: XCTestCase {
    func testSnapshotEncodingIsSecretFree() throws {
        let seat = SeatSnapshot(
            seatID: .seat1,
            auth: .signedIn,
            email: Email("user@example.com"),
            plan: PlanInfo(name: "ultra", includedAmountCents: AmountCents(cents: 20_000)),
            usage: PeriodUsage(
                autoPercentUsed: PercentUsed(unchecked: 10),
                apiPercentUsed: PercentUsed(unchecked: 20),
                totalPercentUsed: PercentUsed(unchecked: 42),
                resetsAt: nil
            ),
            onDemand: nil,
            authDetail: "Usage probe failed (HTTP 401)"
        )
        let aggregate = AggregateSnapshot(seats: [seat])
        let data = try JSONEncoder().encode(aggregate)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("accessToken"))
        XCTAssertFalse(json.contains("refreshToken"))
        XCTAssertFalse(json.contains("rawValue"))
        XCTAssertTrue(json.contains("user@example.com"))
        XCTAssertTrue(json.contains("ultra"))
        XCTAssertTrue(json.contains("totalPercentUsed"))
        XCTAssertTrue(json.contains("includedAmountCents"))
    }

    func testSecretTypesAreNotEncodable() throws {
        let access = try XCTUnwrap(AccessToken("header.payload.super-secret-access-signature"))
        let refresh = try XCTUnwrap(RefreshToken("header.payload.super-secret-refresh-signature"))
        let apiKey = try XCTUnwrap(APIKey("sk-super-secret-api-key"))
        let credential = Credential.session(
            access: access,
            refresh: refresh,
            expiresAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertFalse(isEncodable(access))
        XCTAssertFalse(isEncodable(refresh))
        XCTAssertFalse(isEncodable(apiKey))
        XCTAssertFalse(isEncodable(credential))
        XCTAssertFalse(isEncodable(Credential.apiKey(apiKey)))
    }

    private func isEncodable(_ value: Any) -> Bool {
        value is any Encodable
    }
}
