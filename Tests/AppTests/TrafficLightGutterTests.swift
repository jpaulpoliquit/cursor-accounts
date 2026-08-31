@testable import CursorBar
import XCTest

final class TrafficLightGutterTests: XCTestCase {
    func testUsesFallbackUntilButtonsAreLaidOut() {
        XCTAssertEqual(LiquidGlass.trafficLightGutter(zoomMaxXInView: 0, zoomLaidOut: false), 80)
        XCTAssertEqual(LiquidGlass.trafficLightGutter(zoomMaxXInView: 70, zoomLaidOut: false), 80)
    }

    func testNoGutterWhenLightsAreAlreadyLeftOfThePage() {
        XCTAssertEqual(LiquidGlass.trafficLightGutter(zoomMaxXInView: 0, zoomLaidOut: true), 0)
        XCTAssertEqual(LiquidGlass.trafficLightGutter(zoomMaxXInView: -12, zoomLaidOut: true), 0)
    }

    func testGutterClearsLightsWhenThePageStartsUnderThem() {
        XCTAssertEqual(LiquidGlass.trafficLightGutter(zoomMaxXInView: 70, zoomLaidOut: true), 86)
        XCTAssertEqual(LiquidGlass.trafficLightGutter(zoomMaxXInView: 150, zoomLaidOut: true), 166)
    }
}
