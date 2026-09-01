import XCTest

final class ProductNameSourceTests: XCTestCase {
    func testUserFacingBrandIsCursorAccounts() throws {
        let name = try source("Sources/Domain/ProductName.swift")
        XCTAssertTrue(name.contains("static let display = \"Cursor Accounts\""))
        XCTAssertFalse(name.contains("\"CursorBar\""))
        XCTAssertFalse(name.contains("\"MultiCursor\""))

        let header = try source("Sources/App/Dashboard/DashboardIdentityHeader.swift")
        XCTAssertTrue(header.contains("return ProductName.display"))
        XCTAssertFalse(header.contains("return \"CursorBar\""))
        XCTAssertFalse(header.contains("return \"MultiCursor\""))

        let rail = try source("Sources/App/Dashboard/DashboardSettingsRailView.swift")
        XCTAssertTrue(rail.contains("Text(ProductName.display)"))
        XCTAssertFalse(rail.contains("Text(\"CursorBar\")"))
        XCTAssertFalse(rail.contains("Text(\"MultiCursor\")"))

        let prompts = try source("Sources/App/Auth/ConfirmationPrompts.swift")
        XCTAssertTrue(prompts.contains("from \\(ProductName.display) only"))
        XCTAssertFalse(prompts.contains("from CursorBar only"))
        XCTAssertFalse(prompts.contains("from MultiCursor only"))

        let menu = try source("Sources/App/MenuBarRoot.swift")
        XCTAssertTrue(menu.contains("Quit \\(ProductName.display)"))
        XCTAssertTrue(menu.contains("model.updates.menuTitle"))
        XCTAssertTrue(menu.contains("checkAndPresent"))
        XCTAssertTrue(menu.contains("Show usage in menu bar"))

        let updates = try source("Sources/App/AppUpdateController.swift")
        XCTAssertTrue(updates.contains("Check for Updates"))
        XCTAssertTrue(updates.contains("Update Available"))
        XCTAssertTrue(menu.contains("menuBarUsage"))
        XCTAssertFalse(menu.contains("Active:"))
        XCTAssertFalse(menu.contains("aggregateLine"))
        XCTAssertFalse(menu.contains("focusedSummaryLine"))
        XCTAssertFalse(menu.contains("activeStatusHeader"))
        XCTAssertFalse(menu.contains("Quit CursorBar"))
        XCTAssertFalse(menu.contains("Quit MultiCursor"))
        XCTAssertFalse(menu.contains("MC ·"))

        let dashboard = try source("Sources/App/Dashboard/DashboardView.swift")
        XCTAssertFalse(dashboard.contains("\"MultiCursor\""))
        XCTAssertFalse(dashboard.contains("\"Cursor Accounts\""))
        XCTAssertTrue(dashboard.contains("dashboardTab.title"))
        XCTAssertFalse(dashboard.contains("focused.dashboardTitle"))
    }

    func testProjectShipsCursorAccountsProduct() throws {
        let project = try source("project.yml")
        XCTAssertTrue(project.contains("productName: Cursor Accounts"))
        XCTAssertTrue(project.contains("PRODUCT_NAME: Cursor Accounts"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_CFBundleDisplayName: Cursor Accounts"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_CFBundleName: Cursor Accounts"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER: app.cursorbar"))
        XCTAssertTrue(project.contains("  Cursor Accounts:"))

        let install = try source("Scripts/install.sh")
        XCTAssertTrue(install.contains("SCHEME=\"Cursor Accounts\""))
        XCTAssertFalse(install.contains("SCHEME=\"CursorBar\""))
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative))
    }
}
