import AppKit
import SwiftUI

/// Availability-gated Liquid Glass helpers. Deployment stays macOS 14; APIs require 26+.
enum LiquidGlass {
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    /// System window chrome only. Do not paint a custom title strip or window fill —
    /// that covers the floating toolbar glass and the scroll edge effect.
    /// See [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
    /// and WWDC25 “Build an AppKit app with the new design”.
    static func applyWindowChrome(_ window: NSWindow) {
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        if window.title.isEmpty {
            window.title = "Dashboard"
        }
    }
}

extension View {
    /// Paper panel. Dashboard chrome uses `cursorProfilePaper` for the profile look.
    @ViewBuilder
    func cursorBarContentSurface(cornerRadius: CGFloat = 12) -> some View {
        self.cursorProfilePaper(cornerRadius: cornerRadius)
    }

    @ViewBuilder
    func cursorBarGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func dashboardScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
