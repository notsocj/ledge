import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

/// Rectangle-style window snapping through the Accessibility API: ⌃⌥ + arrow keys for halves and
/// ⌃⌥↩ to fill the screen, or drag a window to the left or right edge (halves) or the top (fill),
/// with a preview of where it will land.
@MainActor
final class WindowSnapper {
    enum Slot { case left, right, top, bottom, fill }

    private var window: AXUIElement?
    private var startPosition: CGPoint?
    private var target: Slot?
    private let preview: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.contentView = NSHostingView(rootView: RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
            .padding(6))
        return panel
    }()

    func start() {
        let shortcuts: [(UInt32, Int, Slot)] = [(1, kVK_LeftArrow, .left), (2, kVK_RightArrow, .right), (3, kVK_UpArrow, .top), (4, kVK_DownArrow, .bottom), (5, kVK_Return, .fill)]
        for (id, key, slot) in shortcuts {
            HotKeys.register(id, key: key, modifiers: controlKey | optionKey) { [weak self] in self?.snapFocusedWindow(to: slot) }
        }
    }

    func stop() {
        for id in UInt32(1)...5 { HotKeys.unregister(id) }
        reset()
    }

    // MARK: Dragging to an edge

    func mouseDown() {
        reset()
        guard AXIsProcessTrusted() else { return }
        let point = Self.axPoint(NSEvent.mouseLocation)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              let element, let window = Self.window(containing: element) else { return }
        self.window = window
        startPosition = Self.position(of: window)
    }

    func mouseDragged() {
        // Only once the window itself is moving: dragging inside a window (selecting text) isn't a snap.
        guard let window, let startPosition, Self.position(of: window) != startPosition else { return }
        let slot = Self.slot(at: NSEvent.mouseLocation)
        guard slot != target else { return }
        target = slot
        if let slot, let frame = Self.frame(for: slot, on: Self.screen(at: NSEvent.mouseLocation)) {
            preview.setFrame(frame, display: true)
            preview.orderFrontRegardless()
        } else {
            preview.orderOut(nil)
        }
    }

    func mouseUp() {
        if let window, let target, let frame = Self.frame(for: target, on: Self.screen(at: NSEvent.mouseLocation)) {
            Self.move(window, to: frame)
        }
        reset()
    }

    private func reset() {
        window = nil
        startPosition = nil
        target = nil
        preview.orderOut(nil)
    }

    // MARK: Keyboard

    private func snapFocusedWindow(to slot: Slot) {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return }
        let window = focused as! AXUIElement
        let screen = Self.position(of: window).map { Self.screen(at: Self.cocoaPoint($0)) } ?? NSScreen.main
        if let frame = Self.frame(for: slot, on: screen) { Self.move(window, to: frame) }
    }

    // MARK: Geometry (Accessibility uses top-left origin; AppKit uses bottom-left)

    static func slot(at point: NSPoint) -> Slot? {
        guard let screen = screen(at: point) else { return nil }
        let frame = screen.frame
        if point.x <= frame.minX + 1 { return .left }
        if point.x >= frame.maxX - 1 { return .right }
        if point.y >= frame.maxY - 1 { return .fill }
        return nil
    }

    static func frame(for slot: Slot, on screen: NSScreen?) -> NSRect? {
        guard let visible = screen?.visibleFrame else { return nil }
        let halfWidth = (visible.width / 2).rounded(), halfHeight = (visible.height / 2).rounded()
        switch slot {
        case .left: return NSRect(x: visible.minX, y: visible.minY, width: halfWidth, height: visible.height)
        case .right: return NSRect(x: visible.maxX - halfWidth, y: visible.minY, width: halfWidth, height: visible.height)
        case .top: return NSRect(x: visible.minX, y: visible.maxY - halfHeight, width: visible.width, height: halfHeight)
        case .bottom: return NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: halfHeight)
        case .fill: return visible
        }
    }

    private static func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
    private static func axPoint(_ point: NSPoint) -> CGPoint { CGPoint(x: point.x, y: primaryHeight - point.y) }
    private static func cocoaPoint(_ point: CGPoint) -> NSPoint { NSPoint(x: point.x, y: primaryHeight - point.y) }

    private static func window(containing element: AXUIElement) -> AXUIElement? {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if role as? String == kAXWindowRole { return element }
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return (window as! AXUIElement)
    }

    private static func position(of window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success, let value else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func move(_ window: AXUIElement, to frame: NSRect) {
        var origin = CGPoint(x: frame.minX, y: primaryHeight - frame.maxY)
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else { return }
        // Size, move, then size again: some apps clamp the size to the screen the window is still on.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
    }
}
