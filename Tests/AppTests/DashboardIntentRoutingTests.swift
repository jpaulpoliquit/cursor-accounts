@testable import CursorBar
import CursorBarDomain
import XCTest

@MainActor
final class DashboardIntentRoutingTests: XCTestCase {
    func testOnDemandIntentsHitCoordinatorOnceEach() async {
        let gate = RecordingGate()
        gate.off = true
        gate.unlimited = true
        gate.fixed = .fixed(PositiveDollars(190)!)
        var modes: [OnDemandMode] = []
        let coordinator = ConfirmationCommandCoordinator(gate: gate)
        coordinator.configure(
            currentOnDemandMode: { _ in nil },
            policyForSeat: { _ in nil },
            accountLabel: { _ in "john 5" },
            performSignOut: { _ in },
            performSetOnDemand: { _, mode in modes.append(mode) }
        )

        coordinator.requestSetOnDemand(seatID: .seat1, mode: .off)
        coordinator.requestSetOnDemandFixed(seatID: .seat1)
        coordinator.requestSetOnDemand(seatID: .seat1, mode: .unlimited)

        for _ in 0..<20 {
            if modes.count == 3 { break }
            await Task.yield()
        }

        XCTAssertEqual(coordinator.setOnDemandInvocations, 3)
        XCTAssertEqual(modes, [.off, .fixed(PositiveDollars(190)!), .unlimited])
        XCTAssertEqual(Set(gate.seenLabels), ["john 5"])
    }

    func testSharedAppModelIntentSurfaceExistsInSource() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appModel = try String(contentsOf: root.appendingPathComponent("Sources/App/AppModel.swift"))
        let menu = try String(contentsOf: root.appendingPathComponent("Sources/App/Menu/SeatMenuContent.swift"))
        let dash = try String(
            contentsOf: root.appendingPathComponent("Sources/App/Dashboard/DashboardSeatControls.swift")
        )
        let seatCard = try String(
            contentsOf: root.appendingPathComponent("Sources/App/Dashboard/SeatCardView.swift")
        )
        let table = try String(
            contentsOf: root.appendingPathComponent("Sources/App/Dashboard/DashboardAccountTable.swift")
        )
        let dashboardSurface = dash + seatCard + table
        for intent in [
            "beginSignIn(seatID:",
            "reauthenticate(seatID:",
            "cancelSignIn(seatID:",
            "requestSignOutLocally(seatID:",
            "requestSetOnDemand(seatID:",
            "requestSetOnDemandFixed(seatID:",
            "presentOnDemandEditor(seatID:",
        ] {
            XCTAssertTrue(appModel.contains("func \(intent)") || appModel.contains("func \(intent.replacingOccurrences(of: "(seatID:", with: "(seatID:"))"), intent)
            XCTAssertTrue(menu.contains("model.\(intent)") || dashboardSurface.contains("model.\(intent)"), intent)
        }
        XCTAssertTrue(menu.contains("model.beginSignIn(seatID:"))
        XCTAssertTrue(dash.contains("model.beginSignIn(seatID:"))
        XCTAssertTrue(menu.contains("model.requestSetOnDemand(seatID:"))
        XCTAssertTrue(dash.contains("model.requestSetOnDemand(seatID:"))
        XCTAssertTrue(menu.contains("model.requestSetOnDemandFixed(seatID:"))
        XCTAssertTrue(dash.contains("model.requestSetOnDemandFixed(seatID:"))
        XCTAssertTrue(table.contains("model.presentOnDemandEditor(seatID:"))
        XCTAssertTrue(dash.contains("model.requestSignOutLocally(seatID:"))
        XCTAssertFalse(dash.contains("Text(\"Signed in\")"))
        XCTAssertFalse(dash.contains("Text(\"Account\")"))
        XCTAssertFalse(dash.contains("Text(\"Connected\")"))
        XCTAssertFalse(seatCard.contains("Text(\"Signed in\")"))
        XCTAssertFalse(seatCard.contains("Text(\"Desktop bound\")"))
        XCTAssertFalse(dash.contains("pickerStyle(.segmented)"))
        XCTAssertTrue(dash.contains("Set fixed limit…"))
        XCTAssertTrue(appModel.contains("func connectAnotherAccount()"))
        let menuRoot = try String(contentsOf: root.appendingPathComponent("Sources/App/MenuBarRoot.swift"))
        XCTAssertTrue(menuRoot.contains("model.connectAnotherAccount()"))
        XCTAssertTrue(menuRoot.contains("lastRejectMessage"))
        let addCard = try String(
            contentsOf: root.appendingPathComponent("Sources/App/Dashboard/AddAccountCard.swift")
        )
        XCTAssertTrue(addCard.contains("model.connectAnotherAccount()"))
        let connectRow = try String(
            contentsOf: root.appendingPathComponent("Sources/App/Dashboard/DashboardConnectAccountRow.swift")
        )
        XCTAssertTrue(connectRow.contains("model.connectAnotherAccount()"))
        XCTAssertFalse(menuRoot.contains("ForEach(presentation.seats)"))
    }
}

@MainActor
private final class RecordingGate: ConfirmationGate {
    var off = false
    var unlimited = false
    var fixed: OnDemandMode?
    private(set) var seenLabels: [String] = []

    func confirmLocalSignOut(accountLabel: String) -> Bool { false }
    func confirmOnDemandOff(accountLabel: String) -> Bool {
        seenLabels.append(accountLabel)
        return off
    }

    func confirmOnDemandUnlimited(accountLabel: String) -> Bool {
        seenLabels.append(accountLabel)
        return unlimited
    }

    func promptFixedOnDemand(accountLabel: String, policy: UsagePolicy?) -> OnDemandMode? {
        seenLabels.append(accountLabel)
        return fixed
    }
}
