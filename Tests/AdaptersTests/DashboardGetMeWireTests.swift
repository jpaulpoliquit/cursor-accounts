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

    func testEmptyIdentityThrows() {
        let json = #"{}"#
        let dto = try! JSONDecoder().decode(GetMeWireDTO.self, from: Data(json.utf8))
        XCTAssertThrowsError(try DashboardGetMeWire.identity(from: dto))
    }
}
