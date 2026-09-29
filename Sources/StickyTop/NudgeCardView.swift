import AppKit

/// The reminder that slides in when a fresh note nudges. Click to dismiss.
final class NudgeCardView: NSView {
    var onClick: (() -> Void)?

    private let leadField = NSTextField(labelWithString: "")
    private let messageField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(white: 0, alpha: 0.12).cgColor

        leadField.font = .systemFont(ofSize: 9.5, weight: .bold)
        leadField.textColor = Theme.secondaryInk
        messageField.font = .systemFont(ofSize: 13, weight: .semibold)
        messageField.textColor = Theme.ink
        for field in [leadField, messageField] {
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            addSubview(field)
        }
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(lead: String, message: String, fill: NSColor) {
        leadField.attributedStringValue = NSAttributedString(
            string: lead.uppercased(),
            attributes: [.kern: 0.6, .font: leadField.font!, .foregroundColor: Theme.secondaryInk]
        )
        messageField.stringValue = message
        layer?.backgroundColor = fill.cgColor
        setAccessibilityLabel("\(lead): \(message). Click to dismiss.")
        toolTip = "Click to dismiss"
    }

    var message: String { messageField.stringValue }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let inset: CGFloat = 10
        leadField.frame = NSRect(x: inset, y: bounds.height - 18, width: bounds.width - 2 * inset, height: 13)
        messageField.frame = NSRect(x: inset, y: 6, width: bounds.width - 2 * inset, height: 18)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        return frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

extension CALayer {
    /// Explicitly animates a color property (view-backing layers skip implicit animations).
    func crossFade(_ keyPath: String, to value: CGColor, duration: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = (presentation() ?? self).value(forKeyPath: keyPath)
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        add(animation, forKey: keyPath)
    }
}
