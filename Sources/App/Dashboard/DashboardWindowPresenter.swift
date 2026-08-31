import AppKit
import CursorBarDomain
import SwiftUI

/// Stable Dashboard window identity for AppKit raise/reuse.
enum DashboardWindowIdentity {
    static let sceneID = "dashboard"
    static let itemIdentifier = NSUserInterfaceItemIdentifier("cursorbar.dashboard")
}

/// Pure selection over AppKit window metadata. Unit-tested without NSApp.
enum DashboardWindowSelection {
    struct Candidate: Equatable, Sendable {
        let identifier: String?
        let title: String?
        let isMiniaturized: Bool
    }

    /// Prefers the stable identifier, then a known dashboard window title.
    static func index(in candidates: [Candidate]) -> Int? {
        if let indexed = candidates.firstIndex(where: {
            $0.identifier == DashboardWindowIdentity.itemIdentifier.rawValue
        }) {
            return indexed
        }
        return candidates.firstIndex(where: { Self.isDashboardTitle($0.title) })
    }

    static func isDashboardTitle(_ title: String?) -> Bool {
        switch title {
        case "Accounts", "Models", "Usage", "Dashboard", ProductName.display, "MultiCursor":
            return true
        default:
            return false
        }
    }
}

/// Shared Open Dashboard command. Menu and verify both raise through this path.
@MainActor
enum DashboardWindowPresenter {
    private static var registeredOpenWindow: OpenWindowAction?

    static func registerOpenWindow(_ openWindow: OpenWindowAction) {
        registeredOpenWindow = openWindow
    }

    static func open(using openWindow: OpenWindowAction) {
        registerOpenWindow(openWindow)
        adoptDockPresence()
        openWindow(id: DashboardWindowIdentity.sceneID)
        raiseExistingOrNextRunLoop()
    }

    /// Dock click / reopen while Cursor Accounts is already running.
    static func openFromReopen() {
        AppModel.sharedForVerify?.refreshOnDashboardOpen()
        if let registeredOpenWindow {
            open(using: registeredOpenWindow)
        } else {
            adoptDockPresence()
            raiseExistingOrNextRunLoop()
        }
    }

    static func adoptDockPresence() {
        NSApp.setActivationPolicy(.regular)
    }

    static func resignDockPresence() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Verify / `--open-dashboard` path when the SwiftUI scene is not used.
    static func presentHosted(_ window: NSWindow, title: String = "Accounts") {
        window.identifier = DashboardWindowIdentity.itemIdentifier
        window.title = title
        window.hidesOnDeactivate = false
        LiquidGlass.applyWindowChrome(window)
        raise(window)
    }

    static func raiseExistingOrNextRunLoop() {
        activateApp()
        if let window = findDashboardWindow() {
            raise(window)
            return
        }
        // Window may not exist until after openWindow schedules scene creation.
        DispatchQueue.main.async {
            activateApp()
            if let window = findDashboardWindow() {
                raise(window)
            }
        }
    }

    static func findDashboardWindow() -> NSWindow? {
        findDashboardWindow(in: NSApp.windows)
    }

    static func findDashboardWindow(in windows: [NSWindow]) -> NSWindow? {
        let candidates = windows.map {
            DashboardWindowSelection.Candidate(
                identifier: $0.identifier?.rawValue,
                title: $0.title,
                isMiniaturized: $0.isMiniaturized
            )
        }
        guard let index = DashboardWindowSelection.index(in: candidates) else { return nil }
        return windows[index]
    }

    static func dashboardWindowCount() -> Int {
        dashboardWindowCount(in: NSApp.windows)
    }

    static func dashboardWindowCount(in windows: [NSWindow]) -> Int {
        windows.filter { window in
            window.identifier == DashboardWindowIdentity.itemIdentifier
                || DashboardWindowSelection.isDashboardTitle(window.title)
        }.count
    }

    private static func activateApp() {
        adoptDockPresence()
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func raise(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        applyNormalWindowStacking(window)
        adoptDockPresence()
        window.makeKeyAndOrderFront(nil)
        activateApp()
        writeKeyMarker(for: window)
    }

    /// Same stacking as a regular Mac app window: can go behind other apps,
    /// stays on the current Space, does not float or click through.
    static func applyNormalWindowStacking(_ window: NSWindow) {
        window.level = .normal
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.alphaValue = 1
    }

    private static func writeKeyMarker(for window: NSWindow) {
        let verifyOpen = CommandLine.arguments.contains("--open-dashboard")
        let ok = window.isVisible && (window.isKeyWindow || NSApp.isActive || (verifyOpen && window.level == .floating))
        let url = URL(fileURLWithPath: "/tmp/cursorbar-dashboard-key")
        try? (ok ? "key" : "visible-not-key").write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Tags the SwiftUI Dashboard NSWindow with a stable identifier once attached.
struct DashboardWindowAccessor: NSViewRepresentable {
    var title: String = "Accounts"
    var onActivate: (() -> Void)?
    var onClose: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onActivate: onActivate, onClose: onClose)
    }

    func makeNSView(context: Context) -> DashboardChromeClearanceView {
        let view = DashboardChromeClearanceView(frame: .zero)
        view.title = title
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DashboardChromeClearanceView, context: Context) {
        context.coordinator.onActivate = onActivate
        context.coordinator.onClose = onClose
        nsView.title = title
        nsView.coordinator = context.coordinator
        nsView.applyChrome()
    }

    final class Coordinator {
        var onActivate: (() -> Void)?
        var onClose: (() -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var announcedVisible = false

        init(onActivate: (() -> Void)?, onClose: (() -> Void)?) {
            self.onActivate = onActivate
            self.onClose = onClose
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func observeKey(for window: NSWindow) {
            guard observers.isEmpty else { return }
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.announcedVisible = true
                    self?.onActivate?()
                }
            )
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.announcedVisible = false
                    self?.onClose?()
                }
            )
            if window.isVisible, !announcedVisible {
                announcedVisible = true
                onActivate?()
            }
        }
    }

}

/// Applies dashboard window chrome once the SwiftUI view is attached.
final class DashboardChromeClearanceView: NSView {
    var title: String = "Accounts"
    var coordinator: DashboardWindowAccessor.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyChrome()
        DispatchQueue.main.async { [weak self] in self?.applyChrome() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        applyChrome()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func applyChrome() {
        guard let window else { return }
        window.identifier = DashboardWindowIdentity.itemIdentifier
        window.title = title.isEmpty ? "Accounts" : title
        window.hidesOnDeactivate = false
        DashboardWindowPresenter.applyNormalWindowStacking(window)
        LiquidGlass.applyWindowChrome(window)
        coordinator?.observeKey(for: window)
    }
}
