import AppKit

/// Keeps NSApplicationDelegate hook for future AppKit seams. Dashboard verify opens from AppModel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let root = VerifyUsageCacheSeed.argumentURL() else { return }
        VerifyUsageCacheSeed.write(to: root)
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {}

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DashboardWindowPresenter.openFromReopen()
        return true
    }
}