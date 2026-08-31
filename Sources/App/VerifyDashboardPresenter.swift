import AppKit
import CursorBarDomain
import SwiftUI

@MainActor
enum VerifyDashboardPresenter {
    private static var window: NSWindow?

    static func applyLaunchOptions(to model: AppModel) {
        for arg in CommandLine.arguments {
            if arg.hasPrefix("--dashboard-tab=") {
                let raw = String(arg.dropFirst("--dashboard-tab=".count))
                if let tab = DashboardTab(rawValue: raw) {
                    model.dashboardTab = tab
                }
            }
            if arg.hasPrefix("--account-layout=") {
                let raw = String(arg.dropFirst("--account-layout=".count))
                switch raw {
                case DashboardAccountLayout.table.rawValue:
                    model.accountLayout = .table
                case DashboardAccountLayout.detail.rawValue, "list":
                    model.accountLayout = .detail
                default:
                    break
                }
            }
            #if DEBUG
            if arg.hasPrefix("--dashboard-layout=") {
                let raw = String(arg.dropFirst("--dashboard-layout=".count))
                if let layout = DashboardLayoutPrototype(rawValue: raw) {
                    model.dashboardLayoutPrototype = layout
                }
            }
            #endif
        }
    }

    static func presentIfRequested(model: AppModel) {
        guard CommandLine.arguments.contains("--open-dashboard") else { return }
        applyLaunchOptions(to: model)
        model.refreshOnDashboardOpen()
        if let window {
        DashboardWindowPresenter.presentHosted(window, title: model.dashboardTab.title)
        scheduleScreenshotIfRequested(window: window, tab: model.dashboardTab)
        return
        }

        let hosting = NSHostingController(rootView: Host(model: model))
        hosting.sceneBridgingOptions = .toolbars
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        let tallUsage = model.dashboardTab == .usage
        window.setContentSize(NSSize(width: 860, height: tallUsage ? 1100 : 800))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        DashboardWindowPresenter.presentHosted(window, title: model.dashboardTab.title)
        scheduleScreenshotIfRequested(window: window, tab: model.dashboardTab)

        let marker = URL(fileURLWithPath: "/tmp/cursorbar-dashboard-opened")
        try? "opened".write(to: marker, atomically: true, encoding: .utf8)
    }

    private static func screenshotPath() -> String? {
        for arg in CommandLine.arguments {
            if arg.hasPrefix("--screenshot-dashboard=") {
                let path = String(arg.dropFirst("--screenshot-dashboard=".count))
                return path.isEmpty ? nil : path
            }
        }
        return nil
    }

    private static func scheduleScreenshotIfRequested(window: NSWindow, tab: DashboardTab) {
        guard let path = screenshotPath() else { return }
        let delay: TimeInterval
        switch tab {
        case .accounts:
            delay = 8.0
        case .models, .usage:
            delay = 10.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            captureContent(window: window, to: path)
        }
    }

    private static func captureContent(window: NSWindow, to path: String) {
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        let windowID = CGWindowID(window.windowNumber)
        let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
        let rep: NSBitmapImageRep?
        if let cgImage {
            rep = NSBitmapImageRep(cgImage: cgImage)
        } else if let view = window.contentView {
            let bounds = view.bounds
            let cache = view.bitmapImageRepForCachingDisplay(in: bounds)
            if let cache {
                view.cacheDisplay(in: bounds, to: cache)
            }
            rep = cache
        } else {
            return
        }
        guard let rep, let data = rep.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
        try? "ok".write(to: URL(fileURLWithPath: path + ".done"), atomically: true, encoding: .utf8)
    }

    private struct Host: View {
        @Bindable var model: AppModel

        var body: some View {
            DashboardView(model: model)
                .frame(minWidth: 720, minHeight: 560)
                .preferredColorScheme(
                    CommandLine.arguments.contains("--dashboard-dark") ? .dark : nil
                )
        }
    }
}
