import AppKit
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

    /// Prefers the stable identifier, then titled "Dashboard".
    static func index(in candidates: [Candidate]) -> Int? {
        if let indexed = candidates.firstIndex(where: {
            $0.identifier == DashboardWindowIdentity.itemIdentifier.rawValue
        }) {
            return indexed
        }
        return candidates.firstIndex(where: { $0.title == "Dashboard" })
    }
}

/// Shared Open Dashboard command. Menu and verify both raise through this path.
@MainActor
enum DashboardWindowPresenter {
    static func open(using openWindow: OpenWindowAction) {
        openWindow(id: DashboardWindowIdentity.sceneID)
        raiseExistingOrNextRunLoop()
    }

    /// Verify / `--open-dashboard` path when the SwiftUI scene is not used.
    static func presentHosted(_ window: NSWindow) {
        window.identifier = DashboardWindowIdentity.itemIdentifier
        window.title = "Dashboard"
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
            window.identifier == DashboardWindowIdentity.itemIdentifier || window.title == "Dashboard"
        }.count
    }

    private static func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func raise(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.hidesOnDeactivate = false
        let verifyOpen = CommandLine.arguments.contains("--open-dashboard")
        // Pulse above normal apps so LSUIElement can surface without a Dock icon.
        // Verify launches keep floating so Cursor IDE focus steal cannot hide the dashboard.
        window.level = .floating
        window.collectionBehavior.insert(.moveToActiveSpace)
        if verifyOpen {
            NSApp.setActivationPolicy(.regular)
        }
        activateApp()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        activateApp()
        DispatchQueue.main.async {
            if !verifyOpen {
                window.level = .normal
            }
            window.makeKeyAndOrderFront(nil)
            activateApp()
            writeKeyMarker(for: window)
        }
        // Second pulse: LSUIElement activation is racy against the host IDE.
        if verifyOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                window.level = .floating
                activateApp()
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
                writeKeyMarker(for: window)
            }
        }
        writeKeyMarker(for: window)
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
    var title: String = "Dashboard"
    var onActivate: (() -> Void)?
    var onClose: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onActivate: onActivate, onClose: onClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            Self.tag(view.window, title: title, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onActivate = onActivate
        context.coordinator.onClose = onClose
        Self.tag(nsView.window, title: title, coordinator: context.coordinator)
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

    private static func tag(_ window: NSWindow?, title: String, coordinator: Coordinator) {
        guard let window else { return }
        window.identifier = DashboardWindowIdentity.itemIdentifier
        window.title = title.isEmpty ? "Dashboard" : title
        window.hidesOnDeactivate = false
        LiquidGlass.applyWindowChrome(window)
        coordinator.observeKey(for: window)
    }
}
