import AppKit
import StickyCore

/// Invisible strip or corner that resizes its borderless window when dragged.
final class ResizeHandleView: NSView {
    let edges: ResizeEdges
    var onResizeEnded: (() -> Void)?
    /// Draws the diagonal grip lines (bottom-right corner only).
    var drawsGrip = false {
        didSet { if drawsGrip != oldValue { needsDisplay = true } }
    }

    private var startFrame = NSRect.zero
    private var startMouse = NSPoint.zero
    private var trackingArea: NSTrackingArea?

    init(edges: ResizeEdges) {
        self.edges = edges
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // .activeAlways: the app is usually inactive, but cursors should still update.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { cursor.set() }
    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startFrame = window.frame
        startMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let delta = CGSize(width: now.x - startMouse.x, height: now.y - startMouse.y)
        window.setFrame(NoteGeometry.resized(startFrame, edges: edges, delta: delta), display: true)
        cursor.set()
    }

    override func mouseUp(with event: NSEvent) {
        onResizeEnded?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard drawsGrip else { return }
        let lines = NSBezierPath()
        for inset in stride(from: CGFloat(4), through: 12, by: 4) {
            lines.move(to: NSPoint(x: bounds.maxX - inset, y: bounds.minY + 2))
            lines.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.minY + inset))
        }
        lines.lineWidth = 1
        lines.lineCapStyle = .round
        NSColor(white: 0, alpha: 0.28).setStroke()
        lines.stroke()
    }

    private var cursor: NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch edges {
            case .left: position = .left
            case .right: position = .right
            case .bottom: position = .bottom
            case [.left, .bottom]: position = .bottomLeft
            default: position = .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
        switch edges {
        case .left, .right: return .resizeLeftRight
        case .bottom: return .resizeUpDown
        default: return .crosshair
        }
    }
}
