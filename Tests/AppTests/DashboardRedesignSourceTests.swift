import XCTest

final class DashboardRedesignSourceTests: XCTestCase {
    func testDashboardIsTabbedNotOneScrollingPage() throws {
        let dashboard = try source("Sources/App/Dashboard/DashboardView.swift")
        XCTAssertFalse(dashboard.contains("accountGrid"))
        XCTAssertTrue(dashboard.contains("DashboardProfileColumnView"))
        XCTAssertTrue(dashboard.contains("dashboardVisible"))
        XCTAssertTrue(dashboard.contains("refreshOnDashboardOpen()"))
        XCTAssertTrue(dashboard.contains("noteDashboardClosed()"))
        XCTAssertTrue(dashboard.contains("onDisappear"))
        XCTAssertFalse(dashboard.contains("DashboardPrototypeSwitcher"))
    }

    func testAccountsTableAndModelTableExist() throws {
        let accounts = try source("Sources/App/Dashboard/DashboardAccountsPane.swift")
        let table = try source("Sources/App/Dashboard/DashboardAccountTable.swift")
        let models = try source("Sources/App/Dashboard/UsageModelCatalogView.swift")
        XCTAssertTrue(accounts.contains("DashboardAccountLayout"))
        XCTAssertTrue(accounts.contains("layout.symbolName"))
        XCTAssertFalse(accounts.contains("Text(layout.title)"))
        let layout = try source("Sources/Domain/DashboardAccountSort.swift")
        XCTAssertTrue(layout.contains("tablecells"))
        XCTAssertTrue(layout.contains("list.bullet"))
        XCTAssertTrue(accounts.contains("DashboardConnectAccountRow"))
        XCTAssertTrue(accounts.contains("layoutSwitcher"))
        XCTAssertTrue(accounts.contains("pickerStyle(.segmented)"))
        XCTAssertTrue(accounts.contains("DashboardAccountTable"))
        XCTAssertFalse(accounts.contains("SeatCardView"))
        XCTAssertFalse(accounts.contains("countCopy"))
        XCTAssertTrue(table.contains("accountSort"))
        XCTAssertTrue(table.contains("ActiveMenuMarker"))
        XCTAssertTrue(table.contains("revealedEmail"))
        XCTAssertTrue(table.contains("CursorProfileAvatar"))
        XCTAssertFalse(table.contains("headerDivider"))
        XCTAssertFalse(table.contains("sortHeader(\"Active\""))
        XCTAssertFalse(table.contains("Color.accentColor"))
        XCTAssertTrue(table.contains(".reset"))
        let meter = try source("Sources/App/Dashboard/DashboardSortHeader.swift")
        XCTAssertTrue(meter.contains("HStack(spacing: 6)"))
        XCTAssertFalse(meter.contains("chartAccent"))
        XCTAssertTrue(models.contains("DashboardModelOrdering"))
        XCTAssertTrue(models.contains("DashboardSortHeader"))
    }

    func testUsageAndModelsAreSeparateSurfaces() throws {
        let usage = try source("Sources/App/Dashboard/DashboardUsagePane.swift")
        let models = try source("Sources/App/Dashboard/DashboardModelsPane.swift")
        let insights = try source("Sources/App/Dashboard/UsageInsightsView.swift")
        XCTAssertTrue(usage.contains("includeModels: false"))
        XCTAssertTrue(usage.contains("UsageChartView"))
        XCTAssertFalse(usage.contains("UsageModelCatalogView"))
        XCTAssertTrue(models.contains("UsageModelCatalogView"))
        XCTAssertFalse(models.contains("UsageChartView"))
        XCTAssertTrue(insights.contains("includeModels"))
    }

    func testProductionShipsProfileColumn() throws {
        let dashboard = try source("Sources/App/Dashboard/DashboardView.swift")
        XCTAssertTrue(dashboard.contains("DashboardProfileColumnView(model: model, dashboardVisible: model.dashboardVisible)"))
        XCTAssertFalse(dashboard.contains("DashboardSettingsRailView"))
        XCTAssertFalse(dashboard.contains("DashboardInspectorView"))
    }

    func testDashboardUsesGlassTitleBar() throws {
        let dashboard = try source("Sources/App/Dashboard/DashboardView.swift")
        let chrome = try source("Sources/App/Design/LiquidGlass.swift")
        let app = try source("Sources/App/CursorBarApp.swift")
        let column = try source("Sources/App/Dashboard/DashboardProfileColumnView.swift")
        XCTAssertTrue(dashboard.contains(".toolbar"))
        XCTAssertTrue(dashboard.contains("DashboardProfileTabBar"))
        XCTAssertTrue(dashboard.contains("sharedBackgroundVisibility"))
        XCTAssertTrue(dashboard.contains("windowTitle"))
        XCTAssertFalse(dashboard.contains("DashboardGlassTitleBar("))
        XCTAssertFalse(dashboard.contains("dashboardHidesWindowTitle"))
        XCTAssertTrue(chrome.contains("titleVisibility = .visible"))
        XCTAssertTrue(chrome.contains("titlebarAppearsTransparent"))
        XCTAssertTrue(chrome.contains("fullSizeContentView"))
        XCTAssertTrue(chrome.contains("titlebarSeparatorStyle = .none"))
        XCTAssertFalse(chrome.contains("syncBackground"))
        XCTAssertFalse(chrome.contains("NSToolbar(identifier"))
        XCTAssertFalse(app.contains("hiddenTitleBar"))
        XCTAssertTrue(app.contains("windowToolbarStyle(.unified)"))
        XCTAssertTrue(column.contains("DashboardTabBody"))
        XCTAssertTrue(column.contains("dashboardScrollEdge"))
        let titleBar = try source("Sources/App/Dashboard/DashboardGlassTitleBar.swift")
        XCTAssertTrue(titleBar.contains("pickerStyle(.segmented)"))
        XCTAssertTrue(titleBar.contains("DashboardProfileTabBar"))
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative))
    }
}
