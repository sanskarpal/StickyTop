import AppKit
import StickyCore

/// Owns one note's panel and keeps the `Note` model in sync with what's on screen.
@MainActor
final class NoteWindowController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private(set) var note: Note
    let panel: NotePanel
    let textView: NoteTextView

    private let container = NoteContainerView()
    private unowned let manager: NoteManager
    /// Text edited since the last archive into `note.richText`.
    private var textIsDirty = false
    /// Set while we move the panel ourselves, so delegate callbacks don't echo.
    private var isApplyingFrame = false
    private var isHovering = false

    var id: UUID { note.id }

    init(note: Note, manager: NoteManager) {
        self.note = note
        self.manager = manager
        let displayedFrame = note.isCollapsed ? NoteGeometry.collapsed(note.frame) : note.frame
        panel = NotePanel(contentRect: displayedFrame)
        textView = NoteTextView(frame: NSRect(origin: .zero, size: note.frame.size))
        super.init()

        configureViews()
        loadText()
        applyColor()
        applyOpacity(animated: false)
        applyCollapsedState(animated: false)

        panel.delegate = self
        panel.keyEquivalentHandler = { [weak self] event in
            self?.handleKeyEquivalent(event) ?? false
        }
    }

    // MARK: Setup

    private func configureViews() {
        panel.contentView = container

        let scrollView = container.scrollView
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.insertionPointColor = Theme.ink
        textView.typingAttributes = Theme.typingAttributes
        textView.delegate = self
        textView.noteMenuProvider = { [weak self] in self?.makeNoteMenu() }
        scrollView.documentView = textView

        let header = container.header
        header.onClose = { [weak self] in self?.delete() }
        header.onToggleCollapse = { [weak self] in self?.toggleCollapsed() }
        header.menuProvider = { [weak self] in self?.makeNoteMenu() ?? NSMenu() }
        container.onHoverChanged = { [weak self] inside in self?.setHovering(inside) }
        container.onResizeEnded = { [weak self] in self?.manager.saveSoon() }
    }

    private func loadText() {
        guard let storage = textView.textStorage else { return }
        if let attributed = RichText.unarchive(note.richText) {
            storage.setAttributedString(attributed)
        } else {
            storage.setAttributedString(NSAttributedString(string: note.plainText, attributes: Theme.typingAttributes))
        }
        textView.setSelectedRange(NSRange(location: storage.length, length: 0))
    }

    // MARK: Showing

    func show() {
        panel.orderFrontRegardless()
    }

    /// Brings the note forward and puts the caret in it — without activating the
    /// app, so the full-screen app underneath stays put.
    func focus() {
        panel.orderFrontRegardless()
        panel.makeKey()
        if !note.isCollapsed {
            panel.makeFirstResponder(textView)
        }
    }

    func close() {
        panel.delegate = nil
        panel.keyEquivalentHandler = nil
        panel.orderOut(nil)
        panel.close()
    }

    func delete() {
        manager.delete(self)
    }

    // MARK: Model sync

    /// Archives edited text into the model. Called right before saving so typing
    /// doesn't pay for archiving on every keystroke.
    func syncTextToModel() {
        guard textIsDirty, let storage = textView.textStorage else { return }
        note.richText = RichText.archive(storage)
        note.plainText = storage.string
        textIsDirty = false
    }

    func textDidChange(_ notification: Notification) {
        textIsDirty = true
        note.plainText = textView.string
        note.modifiedAt = Date()
        container.header.title = note.title
        manager.saveSoon()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrame else { return }
        recordFrame()
        manager.saveSoon()
    }

    func windowDidResize(_ notification: Notification) {
        panel.invalidateShadow()
        guard !isApplyingFrame else { return }
        recordFrame()
        manager.saveSoon()
    }

    /// Stores the on-screen frame as the note's expanded frame.
    private func recordFrame() {
        let frame = panel.frame
        if note.isCollapsed {
            note.frame = CGRect(
                x: frame.minX, y: frame.maxY - note.frame.height,
                width: frame.width, height: note.frame.height
            )
        } else {
            note.frame = frame
        }
    }

    /// Moves the panel to `frame` (the frame as displayed — collapsed or not).
    func setDisplayedFrame(_ frame: CGRect, animate: Bool = false) {
        isApplyingFrame = true
        panel.setFrame(frame, display: true, animate: animate && panel.isVisible)
        isApplyingFrame = false
        recordFrame()
        panel.invalidateShadow()
    }

    // MARK: Appearance

    func setColor(_ color: NoteColor) {
        note.color = color
        applyColor()
        manager.saveSoon()
    }

    private func applyColor() {
        container.fillColor = note.color.body.nsColor
        container.header.fillColor = note.color.header.nsColor
    }

    func setOpacity(_ opacity: Double) {
        note.opacity = opacity
        isHovering = false // show the new opacity right away
        applyOpacity(animated: true)
        manager.saveSoon()
    }

    /// Translucent notes turn solid while the pointer is over them.
    private func applyOpacity(animated: Bool) {
        let target = CGFloat(isHovering ? 1 : note.opacity)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = target
            }
        } else {
            panel.alphaValue = target
        }
    }

    func setHovering(_ inside: Bool) {
        isHovering = inside
        container.header.setControlsVisible(inside, animated: true)
        container.showsGrip = inside && !note.isCollapsed
        if note.opacity < 1 { applyOpacity(animated: true) }
    }

    func toggleCollapsed() {
        note.isCollapsed.toggle()
        applyCollapsedState(animated: true)
        manager.saveSoon()
    }

    private func applyCollapsedState(animated: Bool) {
        let collapsed = note.isCollapsed
        container.isCollapsed = collapsed
        container.header.title = note.title
        container.header.showsTitle = collapsed
        container.showsGrip = isHovering && !collapsed

        let current = panel.frame
        let expanded = CGRect(
            x: current.minX, y: current.maxY - note.frame.height,
            width: current.width, height: note.frame.height
        )
        let target: CGRect
        if collapsed {
            target = NoteGeometry.collapsed(expanded)
            if panel.firstResponder === textView { panel.makeFirstResponder(nil) }
        } else if let screen = panel.screen ?? NSScreen.main {
            // Expanding near the bottom of the screen shouldn't push text off it.
            target = NoteGeometry.fit(expanded, inside: screen.visibleFrame)
        } else {
            target = expanded
        }
        setDisplayedFrame(target, animate: animated)
    }

    // MARK: Menu

    func makeNoteMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for (index, color) in NoteColor.allCases.enumerated() {
            let item = menu.addItem(withTitle: color.displayName, action: #selector(colorSelected(_:)), keyEquivalent: "\(index + 1)")
            item.keyEquivalentModifierMask = .command
            item.target = self
            item.image = Theme.swatch(for: color)
            item.representedObject = color.rawValue
            item.state = color == note.color ? .on : .off
        }
        menu.addItem(.separator())

        let opacityMenu = NSMenu()
        for level in Note.opacityLevels {
            let item = opacityMenu.addItem(withTitle: "\(Int(level * 100))%", action: #selector(opacitySelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = level
            item.state = abs(level - note.opacity) < 0.01 ? .on : .off
        }
        opacityMenu.addItem(.separator())
        let cycle = opacityMenu.addItem(withTitle: "Cycle Opacity", action: #selector(cycleOpacity), keyEquivalent: "t")
        cycle.keyEquivalentModifierMask = [.command, .option]
        cycle.target = self
        menu.addItem(withTitle: "Opacity", action: nil, keyEquivalent: "").submenu = opacityMenu

        let collapse = menu.addItem(withTitle: note.isCollapsed ? "Expand" : "Collapse", action: #selector(collapseSelected), keyEquivalent: "m")
        collapse.target = self
        menu.addItem(.separator())

        let newNote = menu.addItem(withTitle: "New Note", action: #selector(newNoteSelected), keyEquivalent: "n")
        newNote.target = self
        let delete = menu.addItem(withTitle: "Delete Note", action: #selector(deleteSelected), keyEquivalent: "w")
        delete.target = self
        return menu
    }

    @objc private func colorSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let color = NoteColor(rawValue: raw) else { return }
        setColor(color)
    }

    @objc private func opacitySelected(_ sender: NSMenuItem) {
        guard let level = sender.representedObject as? Double else { return }
        setOpacity(level)
    }

    @objc private func cycleOpacity() { setOpacity(Note.nextOpacity(after: note.opacity)) }
    @objc private func collapseSelected() { toggleCollapsed() }
    @objc private func newNoteSelected() { manager.createNote(cascadingFrom: self) }
    @objc private func deleteSelected() { delete() }

    // MARK: Keyboard

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let editing = panel.firstResponder === textView

        switch (flags, key) {
        case ([.command], "n"): manager.createNote(cascadingFrom: self)
        case ([.command], "w"): delete()
        case ([.command], "m"): toggleCollapsed()
        case ([.command, .option], "t"): cycleOpacity()
        case ([.command], let digit) where Int(digit).map({ (1...NoteColor.allCases.count).contains($0) }) == true:
            setColor(NoteColor.allCases[Int(digit)! - 1])
        case ([.command], "x") where editing: textView.cut(nil)
        case ([.command], "c") where editing: textView.copy(nil)
        case ([.command], "v") where editing: textView.paste(nil)
        case ([.command, .option, .shift], "v") where editing: textView.pasteAsPlainText(nil)
        case ([.command], "a") where editing: textView.selectAll(nil)
        case ([.command], "z") where editing: textView.performUndo()
        case ([.command, .shift], "z") where editing: textView.performRedo()
        case ([.command], "b") where editing: textView.toggleFontTrait(.boldFontMask)
        case ([.command], "i") where editing: textView.toggleFontTrait(.italicFontMask)
        case ([.command], "u") where editing: textView.toggleAttribute(.underlineStyle)
        case ([.command, .shift], "x") where editing: textView.toggleAttribute(.strikethroughStyle)
        case ([.command], "=") where editing, ([.command], "+") where editing,
             ([.command, .shift], "=") where editing, ([.command, .shift], "+") where editing:
            textView.adjustFontSize(by: 1)
        case ([.command], "-") where editing: textView.adjustFontSize(by: -1)
        default: return false
        }
        return true
    }
}
