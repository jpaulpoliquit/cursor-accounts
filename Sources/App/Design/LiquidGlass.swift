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

    /// Minimum leading gutter when a view shares the traffic-light row.
    static let trafficLightsLeading: CGFloat = 80
    static let trafficLightsGap: CGFloat = 16

    /// Traffic lights only. Keep a real title-bar strip so macOS 27’s SwiftUI
    /// `ThemeWidgetView` lights can draw. Content-under-titlebar covers them.
    static func applyWindowChrome(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.remove(.fullSizeContentView)
        window.toolbarStyle = .automatic
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.isMovableByWindowBackground = true
        let titleFill = pageFill(for: window)
        window.isOpaque = true
        window.backgroundColor = titleFill
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.hasShadow = true
        if let content = window.contentView {
            content.wantsLayer = true
            content.layer?.isOpaque = true
            content.layer?.backgroundColor = titleFill.cgColor
        }
        paintTitlebarToMatchPage(window)
    }

    private static func pageFill(for window: NSWindow) -> NSColor {
        let dark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 20 / 255, green: 20 / 255, blue: 20 / 255, alpha: 1)
            : NSColor(srgbRed: 248 / 255, green: 248 / 255, blue: 248 / 255, alpha: 1)
    }

    /// Fill the title-bar strip so it does not go clear with the window.
    /// Hide the 1pt rule only. Never hide glass that hosts the traffic lights.
    private static func paintTitlebarToMatchPage(_ window: NSWindow) {
        let lightViews = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { $0 }
        guard let close = lightViews.first, let titlebar = close.superview else { return }
        let lights: Set<ObjectIdentifier> = Set(lightViews.map { ObjectIdentifier($0) })
        func hostsTrafficLights(_ view: NSView) -> Bool {
            if lights.contains(ObjectIdentifier(view)) { return true }
            return view.subviews.contains { hostsTrafficLights($0) }
        }
        func intersectsTrafficLights(_ view: NSView) -> Bool {
            guard let parent = view.superview else { return hostsTrafficLights(view) }
            return lightViews.contains { light in
                let frame = light.convert(light.bounds, to: parent)
                return view.frame.intersects(frame)
            }
        }
        func paint(_ view: NSView) {
            if view == window.contentView { return }
            let typeName = String(describing: type(of: view))
            let keepVisible = hostsTrafficLights(view) || intersectsTrafficLights(view)
            if typeName.localizedCaseInsensitiveContains("separator") {
                view.isHidden = true
                return
            }
            if !keepVisible, view.bounds.height > 0, view.bounds.height <= 2,
               view.bounds.width >= 8
            {
                view.isHidden = true
                return
            }
            if typeName.contains("TitlebarBackground") || typeName.contains("TitlebarDecoration") {
                view.isHidden = false
            } else if keepVisible {
                view.isHidden = false
            }
            for subview in view.subviews {
                paint(subview)
            }
        }
        paint(titlebar)
        if let container = titlebar.superview, container != window.contentView {
            paint(container)
        }
        for light in lightViews {
            light.isHidden = false
            light.alphaValue = 1
            var ancestor: NSView? = light
            while let current = ancestor, current != window.contentView {
                current.isHidden = false
                current.alphaValue = 1
                ancestor = current.superview
            }
        }
    }

    /// `zoomMaxXInView` is the green button’s maxX in the SwiftUI page’s coordinates.
    static func trafficLightGutter(zoomMaxXInView: CGFloat, zoomLaidOut: Bool) -> CGFloat {
        guard zoomLaidOut else { return trafficLightsLeading }
        if zoomMaxXInView <= 0 { return 0 }
        return max(trafficLightsLeading, zoomMaxXInView + trafficLightsGap)
    }

    static func trafficLightGutter(window: NSWindow, from view: NSView) -> CGFloat {
        guard let zoom = window.standardWindowButton(.zoomButton) else {
            return trafficLightsLeading
        }
        let laidOut = zoom.bounds.width >= 1 && zoom.superview != nil
        let zoomInView = zoom.convert(zoom.bounds, to: view)
        return trafficLightGutter(zoomMaxXInView: zoomInView.maxX, zoomLaidOut: laidOut)
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
