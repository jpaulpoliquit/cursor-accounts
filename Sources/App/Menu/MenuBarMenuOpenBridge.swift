import AppKit
import SwiftUI

/// Fires when the status-item menu opens. SwiftUI MenuBarExtra has no menuWillOpen hook.
struct MenuBarMenuOpenBridge: NSViewRepresentable {
    let onOpen: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpen: onOpen)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onOpen = onOpen
        context.coordinator.attach(to: nsView)
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        var onOpen: () -> Void
        private weak var attachedMenu: NSMenu?

        init(onOpen: @escaping () -> Void) {
            self.onOpen = onOpen
        }

        deinit {
            if attachedMenu?.delegate === self {
                attachedMenu?.delegate = nil
            }
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                guard let menu = Self.statusItemMenu(containing: view) else { return }
                guard menu !== self.attachedMenu else { return }
                self.attachedMenu = menu
                menu.delegate = self
            }
        }

        func menuWillOpen(_ menu: NSMenu) {
            onOpen()
        }

        private static func statusItemMenu(containing view: NSView) -> NSMenu? {
            var candidate: NSView? = view
            while let current = candidate {
                if let button = current as? NSStatusBarButton {
                    return button.menu
                }
                candidate = current.superview
            }
            return nil
        }
    }
}
