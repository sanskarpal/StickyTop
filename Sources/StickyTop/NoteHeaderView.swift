import AppKit

/// The drag bar at the top of a note: drag to move, double-click to collapse,
/// ✕ to delete, ••• for options. Buttons fade in while the pointer is over the note.
final class NoteHeaderView: NSView {
    var onClose: (() -> Void)?
    var onToggleCollapse: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    var fillColor: NSColor = .clear {
        didSet { layer?.backgroundColor = fillColor.cgColor }
    }

    var title: String {
        get { titleField.stringValue }
        set { titleField.stringValue = newValue }
    }

    /// The first line of the note is shown only while collapsed.
    var showsTitle = false {
        didSet { titleField.isHidden = !showsTitle }
    }

    private let closeButton = HeaderButton(symbol: "xmark", label: "Delete Note")
    private let menuButton = HeaderButton(symbol: "ellipsis", label: "Note Options")
    private let titleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        menuButton.target = self
        menuButton.action = #selector(menuClicked)

        titleField.font = .systemFont(ofSize: 11, weight: .semibold)
        titleField.textColor = Theme.secondaryInk
        titleField.lineBreakMode = .byTruncatingTail
        titleField.alignment = .center
        titleField.isHidden = true

        addSubview(titleField)
        addSubview(closeButton)
        addSubview(menuButton)
        setControlsVisible(false, animated: false)
        layoutParts()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setControlsVisible(_ visible: Bool, animated: Bool) {
        let alpha: CGFloat = visible ? 1 : 0
        for button in [closeButton, menuButton] {
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    button.animator().alphaValue = alpha
                }
            } else {
                button.alphaValue = alpha
            }
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutParts()
    }

    private func layoutParts() {
        let side: CGFloat = 18
        let y = (bounds.height - side) / 2
        closeButton.frame = NSRect(x: 5, y: y, width: side, height: side)
        menuButton.frame = NSRect(x: bounds.width - side - 5, y: y, width: side, height: side)
        let titleHeight: CGFloat = 16
        titleField.frame = NSRect(
            x: 28, y: (bounds.height - titleHeight) / 2,
            width: max(0, bounds.width - 56), height: titleHeight
        )
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Clicks on the title label belong to the bar (drag / double-click).
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === titleField ? self : hit
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onToggleCollapse?()
        } else {
            window?.performDrag(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    @objc private func closeClicked() {
        onClose?()
    }

    @objc private func menuClicked() {
        guard let menu = menuProvider?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: menuButton.frame.minX, y: menuButton.frame.minY), in: self)
    }
}

private final class HeaderButton: NSButton {
    init(symbol: String, label: String) {
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryChange)
        imagePosition = .imageOnly
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        contentTintColor = Theme.secondaryInk
        toolTip = label
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
