@testable import CursorBarAdapters
import CursorBarDomain
import XCTest

final class DashboardGetMeWireTests: XCTestCase {
    func testParsesEmailAndDisplayName() throws {
        let json = #"{"email":"user@example.com","firstName":"john","lastName":"5"}"#
        let dto = try JSONDecoder().decode(GetMeWireDTO.self, from: Data(json.utf8))
        let identity = try DashboardGetMeWire.identity(from: dto)
        XCTAssertEqual(identity.email?.value, "user@example.com")
        XCTAssertEqual(identity.displayName?.value, "john 5")
    }

    func testEmailAloneIsUsable() throws {
        let json = #"{"email":"solo@example.com"}"#
        let dto = try JSONDecoder().decode(GetMeWireDTO.self, from: Data(json.utf8))
        let identity = try DashboardGetMeWire.identity(from: dto)
        XCTAssertEqual(identity.email?.value, "solo@example.com")
        XCTAssertNil(identity.displayName)
    }

    func testEmailShapedNameRejectedButEmailKept() throws {
        let json = #"{"email":"user@example.com","firstName":"user@example.com"}"#
        let dto = try JSONDecoder().decode(GetMeWireDTO.self, from: Data(json.utf8))
        let identity = try DashboardGetMeWire.identity(from: dto)
        XCTAssertEqual(identity.email?.value, "user@example.com")
        XCTAssertNil(identity.displayName)
    }

    func testParsesPictureAndTeamMembership() throws {
        let json = #"{"email":"user@example.com","firstName":"Ada","pictureUrl":"https://example.com/ada.png","membershipType":"enterprise"}"#
        let dto = try JSONDecoder().decode(GetMeWireDTO.self, from: Data(json.utf8))
        let identity = try DashboardGetMeWire.identity(from: dto)
        XCTAssertEqual(identity.pictureURL?.absoluteString, "https://example.com/ada.png")
        XCTAssertTrue(identity.isTeamAccount)
    }

    func testParsesProfilePictureUrlAndTeamName() throws {
        let json = #"{"email":"user@example.com","firstName":"Ada","profilePictureUrl":"https://lh3.googleusercontent.com/a/ada","teamName":"NextDecade"}"#
        let dto = try JSONDecoder().decode(GetMeWireDTO.self, from: Data(json.utf8))
        let identity = try DashboardGetMeWire.identity(from: dto)
        XCTAssertEqual(identity.pictureURL?.absoluteString, "https://lh3.googleusercontent.com/a/ada")
        XCTAssertTrue(identity.isTeamAccount)
    }

    func testTeamIdMarksTeamAccount() throws {
        let json = #"{"email":"user@example.com","teamId":42}"#
        let dto = try JSONDecoder().decode(GetMeWireDTO.self, from: Data(json.utf8))
        let identity = try DashboardGetMeWire.identity(from: dto)
        XCTAssertTrue(identity.isTeamAccount)
        XCTAssertNil(identity.pictureURL)
    }

    func testParsesNestedUserPicture() throws {
        let json = #"{"user":{"email":"nested@example.com","picture":"https://example.com/n.png"}}"#
        let dto = try JSONDecoder().decode(GetMeWireDTO.self, from: Data(json.utf8))
        let identity = try DashboardGetMeWire.identity(from: dto)
        XCTAssertEqual(identity.email?.value, "nested@example.com")
        XCTAssertEqual(identity.pictureURL?.absoluteString, "https://example.com/n.png")
    }

    func testEmptyIdentityThrows() {
        let json = #"{}"#
        let dto = try! JSONDecoder().decode(GetMeWireDTO.self, from: Data(json.utf8))
        XCTAssertThrowsError(try DashboardGetMeWire.identity(from: dto))
    }
}
