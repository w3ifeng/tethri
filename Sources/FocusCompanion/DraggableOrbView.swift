import AppKit
import SwiftUI

/// Track the pointer in screen coordinates: local coordinates change as the panel moves.
final class DraggableOrbView<Content: View>: NSHostingView<Content> {
    var onClick: (() -> Void)?
    var onMove: (() -> Void)?
    var onDragEnd: (() -> Void)?
    private var pointerOrigin: NSPoint?
    private var windowOrigin = NSPoint.zero
    private var dragging = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit is PanelResizeView { return hit }
        return hit == nil ? nil : self
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        let grip: CGFloat = 26
        addCursorRect(NSRect(x: 0, y: grip, width: bounds.width, height: max(0, bounds.height - grip)), cursor: .openHand)
        addCursorRect(NSRect(x: 0, y: 0, width: max(0, bounds.width - grip), height: grip), cursor: .openHand)
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        pointerOrigin = window.convertPoint(toScreen: event.locationInWindow)
        windowOrigin = window.frame.origin
        dragging = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = pointerOrigin else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        let dx = pointer.x - start.x, dy = pointer.y - start.y
        guard dragging || hypot(dx, dy) >= 3 else { return }
        dragging = true
        NSCursor.closedHand.set()
        window.setFrameOrigin(NSPoint(x: windowOrigin.x + dx, y: windowOrigin.y + dy))
        onMove?()
    }
    override func mouseUp(with event: NSEvent) {
        guard pointerOrigin != nil else { return }
        pointerOrigin = nil
        NSCursor.openHand.set()
        if dragging { onDragEnd?() }
        else { onClick?() }
        dragging = false
    }
}

enum CompanionPlacement {
    static func chatOrigin(orb: NSRect, chat: NSSize, bounds: NSRect) -> NSPoint {
        let safe = bounds.insetBy(dx: 10, dy: 10)
        let gap: CGFloat = 12
        // Align the chat's bottom with the companion, keeping both in one row.
        let y = min(max(safe.minY, orb.minY), max(safe.minY, safe.maxY - chat.height))
        let right = orb.maxX + gap
        if right + chat.width <= safe.maxX { return NSPoint(x: right, y: y) }
        let left = orb.minX - gap - chat.width
        if left >= safe.minX { return NSPoint(x: left, y: y) }
        // Use vertical placement only when neither side has enough room.
        let x = min(max(safe.minX, orb.midX - chat.width / 2), max(safe.minX, safe.maxX - chat.width))
        let above = orb.maxY + gap
        if above + chat.height <= safe.maxY { return NSPoint(x: x, y: above) }
        let below = orb.minY - gap - chat.height
        if below >= safe.minY { return NSPoint(x: x, y: below) }
        return NSPoint(x: x, y: y)
    }
}

/// A visible corner grip works even for borderless floating panels.
struct ResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelResizeView { PanelResizeView() }
    func updateNSView(_ view: PanelResizeView, context: Context) {}
}
final class PanelResizeView: NSView {
    private var start = NSPoint.zero
    private var original = NSRect.zero
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private static let resizeCursor: NSCursor = {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 5, y: 5)); path.line(to: NSPoint(x: 19, y: 19))
            path.move(to: NSPoint(x: 5, y: 12)); path.line(to: NSPoint(x: 5, y: 5)); path.line(to: NSPoint(x: 12, y: 5))
            path.move(to: NSPoint(x: 12, y: 19)); path.line(to: NSPoint(x: 19, y: 19)); path.line(to: NSPoint(x: 19, y: 12))
            path.lineJoinStyle = .round; path.lineCapStyle = .round
            NSColor.black.setStroke(); path.lineWidth = 4; path.stroke()
            NSColor.white.setStroke(); path.lineWidth = 2; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Drag to resize"
        setAccessibilityLabel("Resize window")
        setAccessibilityHelp("Drag diagonally to change width and height.")
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: Self.resizeCursor) }
    override func draw(_ dirtyRect: NSRect) {
        let plate = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        NSColor(calibratedWhite: 0.10, alpha: 0.92).setFill(); plate.fill()
        NSColor.white.withAlphaComponent(0.4).setStroke(); plate.lineWidth = 1; plate.stroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 7, y: 7)); path.line(to: NSPoint(x: 19, y: 19))
        path.move(to: NSPoint(x: 7, y: 12)); path.line(to: NSPoint(x: 7, y: 7)); path.line(to: NSPoint(x: 12, y: 7))
        path.move(to: NSPoint(x: 14, y: 19)); path.line(to: NSPoint(x: 19, y: 19)); path.line(to: NSPoint(x: 19, y: 14))
        NSColor.white.setStroke(); path.lineWidth = 1.5; path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        start = NSEvent.mouseLocation; original = window.frame
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let pointer = NSEvent.mouseLocation
        let width = min(window.maxSize.width, max(window.minSize.width, original.width + pointer.x - start.x))
        let height = min(window.maxSize.height, max(window.minSize.height, original.height - pointer.y + start.y))
        window.setFrame(NSRect(x: original.minX, y: original.maxY - height, width: width, height: height), display: true)
    }
}
