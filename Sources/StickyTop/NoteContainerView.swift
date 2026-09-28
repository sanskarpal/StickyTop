import AppKit
import StickyCore

/// Root view of a note: rounded paper with the drag bar, the text area and the
/// resize handles laid out on top.
final class NoteContainerView: NSView {
    let header = NoteHeaderView(frame: .zero)
    let scrollView = NSScrollView(frame: .zero)

    var onHoverChanged: ((Bool) -> Void)?

    var onResizeEnded: (() -> Void)? {
        didSet { handles.forEach { $0.onResizeEnded = onResizeEnded } }
    }

    var fillColor: NSColor = .white {
        didSet { layer?.backgroundColor = fillColor.cgColor }
    }

    var isCollapsed = false {
        didSet {
            scrollView.isHidden = isCollapsed
            handles.forEach { $0.isHidden = isCollapsed }
        }
    }

    var showsGrip = false {
        didSet { cornerHandle.drawsGrip = showsGrip }
    }

    private let leftHandle = ResizeHandleView(edges: .left)
    private let rightHandle = ResizeHandleView(edges: .right)
    private let bottomHandle = ResizeHandleView(edges: .bottom)
    private let bottomLeftHandle = ResizeHandleView(edges: [.left, .bottom])
    private let cornerHandle = ResizeHandleView(edges: [.right, .bottom])
    private var handles: [ResizeHandleView] {
        [leftHandle, rightHandle, bottomHandle, bottomLeftHandle, cornerHandle]
    }
    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(white: 0, alpha: 0.14).cgColor

        addSubview(scrollView)
        addSubview(header)
        handles.forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutParts()
    }

    private func layoutParts() {
        let width = bounds.width
        let headerHeight = NoteGeometry.headerHeight
        let bodyHeight = max(0, bounds.height - headerHeight)
        let edge: CGFloat = 5
        let corner: CGFloat = 16

        header.frame = NSRect(x: 0, y: bounds.height - headerHeight, width: width, height: headerHeight)
        scrollView.frame = NSRect(x: 0, y: 0, width: width, height: bodyHeight)
        leftHandle.frame = NSRect(x: 0, y: corner, width: edge, height: max(0, bodyHeight - corner))
        rightHandle.frame = NSRect(x: width - edge, y: corner, width: edge, height: max(0, bodyHeight - corner))
        bottomHandle.frame = NSRect(x: corner, y: 0, width: max(0, width - 2 * corner), height: edge)
        bottomLeftHandle.frame = NSRect(x: 0, y: 0, width: corner, height: corner)
        cornerHandle.frame = NSRect(x: width - corner, y: 0, width: corner, height: corner)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}
