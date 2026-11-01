import Actions
import AppKit
import QuartzCore

/// A small ring around the cursor showing what the hand is doing (spec §2.5). Click-through, never focused,
/// visible on every Space and over full-screen apps.
@MainActor
final class CursorOverlay {
    private static let size: CGFloat = 44
    private let panel: NSPanel
    private let ring = CAShapeLayer()
    private var mode: OverlayMode = .hidden

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = NSView(frame: panel.contentLayoutRect)
        view.wantsLayer = true
        ring.frame = view.bounds
        ring.actions = ["path": NSNull(), "lineWidth": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull()]
        view.layer?.addSublayer(ring)
        panel.contentView = view
    }

    func show(_ state: OverlayState) {
        guard state.mode != .hidden else {
            if mode != .hidden { panel.orderOut(nil) }
            mode = .hidden
            return
        }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: mouse.x - Self.size / 2, y: mouse.y - Self.size / 2))
        if state.mode != mode {
            style(state.mode)
            if mode == .hidden { panel.orderFrontRegardless() }
            mode = state.mode
        }
    }

    private func style(_ mode: OverlayMode) {
        let bounds = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        let accent = NSColor.controlAccentColor.cgColor
        let white = NSColor.white.withAlphaComponent(0.85).cgColor
        ring.lineDashPattern = nil
        switch mode {
        case .hover:
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 10, dy: 10), transform: nil)
            ring.lineWidth = 2
            ring.strokeColor = white
            ring.fillColor = nil
        case .pressed:
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 15, dy: 15), transform: nil)
            ring.lineWidth = 0
            ring.fillColor = accent
        case .dragging:
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 8, dy: 8), transform: nil)
            ring.lineWidth = 4
            ring.strokeColor = accent
            ring.fillColor = nil
        case .scrolling:
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 9, dy: 9), transform: nil)
            ring.lineWidth = 3
            ring.strokeColor = accent
            ring.fillColor = nil
            ring.lineDashPattern = [4, 3]
        case .hidden:
            break
        }
    }
}
