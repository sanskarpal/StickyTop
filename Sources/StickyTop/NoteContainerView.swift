import AppKit
import StickyCore

/// Root view of a note: rounded paper with the drag bar, the text area and the
/// resize handles laid out on top.
final class NoteContainerView: NSView {
    let header = NoteHeaderView(frame: .zero)
    let scrollView = NSScrollView(frame: .zero)
    let nudgeCard = NudgeCardView()
    private let flashLayer = CALayer()

    var onHoverChanged: ((Bool) -> Void)?

    var onResizeEnded: (() -> Void)? {
        didSet { handles.forEach { $0.onResizeEnded = onResizeEnded } }
    }

    var fillColor: NSColor = .white {
        didSet { layer?.backgroundColor = fillColor.cgColor }
    }

    /// Changes the paper color, cross-fading when `animated` (fresh notes' new shade).
    func setFillColor(_ color: NSColor, animated: Bool) {
        if animated, let layer { layer.crossFade("backgroundColor", to: color.cgColor, duration: 0.8) }
        fillColor = color
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
        addSubview(nudgeCard)
        addSubview(header)
        handles.forEach(addSubview)
        nudgeCard.isHidden = true

        flashLayer.backgroundColor = NSColor.white.cgColor
        flashLayer.opacity = 0
        flashLayer.zPosition = 50
        layer?.addSublayer(flashLayer)
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
        nudgeCard.frame = cardFrame
        flashLayer.frame = bounds
    }

    /// Along the bottom edge, where notes are usually blank, so it doesn't hide your text.
    private var cardFrame: NSRect {
        NSRect(x: 8, y: 8, width: max(0, bounds.width - 16), height: 46)
    }

    // MARK: Nudges

    /// Whether the card is (or is animating to be) shown. Flips immediately on
    /// dismiss, unlike `isHidden`, which waits for the fade-out.
    private(set) var isNudgeCardShown = false

    /// Slides the reminder card up from the bottom edge.
    func showNudgeCard(lead: String, message: String, fill: NSColor) {
        nudgeCard.configure(lead: lead, message: message, fill: fill)
        isNudgeCardShown = true
        let final = cardFrame
        nudgeCard.frame = final.offsetBy(dx: 0, dy: -10)
        nudgeCard.alphaValue = 0
        nudgeCard.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            nudgeCard.animator().frame = final
            nudgeCard.animator().alphaValue = 1
        }
    }

    func hideNudgeCard(animated: Bool) {
        guard isNudgeCardShown else { return }
        isNudgeCardShown = false
        guard animated else {
            nudgeCard.isHidden = true
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            nudgeCard.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isNudgeCardShown else { return } // re-shown meanwhile
                self.nudgeCard.isHidden = true
            }
        })
    }

    /// Two soft beats of light and a glowing edge — noticeable, not alarming.
    func playNudgeFlash(glow: NSColor) {
        let beats: [NSNumber] = [0, 1, 0, 0.8, 0]
        let times: [NSNumber] = [0, 0.2, 0.5, 0.7, 1]

        let flash = CAKeyframeAnimation(keyPath: "opacity")
        flash.values = beats.map { NSNumber(value: $0.doubleValue * 0.35) }
        flash.keyTimes = times
        flash.duration = 1.1
        flashLayer.add(flash, forKey: "nudge")

        let width = CAKeyframeAnimation(keyPath: "borderWidth")
        width.values = beats.map { NSNumber(value: 0.5 + $0.doubleValue * 2.5) }
        width.keyTimes = times
        let color = CAKeyframeAnimation(keyPath: "borderColor")
        let base = NSColor(white: 0, alpha: 0.14).cgColor
        color.values = [base, glow.cgColor, base, glow.cgColor, base]
        color.keyTimes = times
        let group = CAAnimationGroup()
        group.animations = [width, color]
        group.duration = 1.1
        layer?.add(group, forKey: "nudge")
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
