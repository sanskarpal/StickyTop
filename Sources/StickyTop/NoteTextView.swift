import AppKit

/// Rich-text editor for a note, with Stickies-style formatting commands and
/// paste cleanup so text copied from dark-mode apps stays readable on paper.
final class NoteTextView: NSTextView {
    /// Supplies the note's own menu (color, opacity, delete…) for right-clicks.
    var noteMenuProvider: (() -> NSMenu?)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if let noteMenu = noteMenuProvider?() {
            let noteItem = NSMenuItem(title: "Note", action: nil, keyEquivalent: "")
            noteItem.submenu = noteMenu
            menu.insertItem(noteItem, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        return menu
    }

    // MARK: Paste

    /// Keeps bold/italic/links/sizes from rich pastes but drops foreign colors,
    /// backgrounds, images and typefaces so the note keeps its look.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard
            pasteboard.availableType(from: [.rtf, .rtfd, .html]) != nil,
            let pasted = pasteboard.readObjects(forClasses: [NSAttributedString.self])?.first as? NSAttributedString,
            pasted.length > 0
        else {
            super.paste(sender)
            return
        }
        insertCleaned(pasted)
    }

    private func insertCleaned(_ source: NSAttributedString) {
        let text = NSMutableAttributedString(attributedString: source)

        // Drop embedded images/attachments (and their placeholder characters).
        var attachmentRanges: [NSRange] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value != nil { attachmentRanges.append(range) }
        }
        for range in attachmentRanges.reversed() {
            text.deleteCharacters(in: range)
        }
        guard text.length > 0 else { return }

        let whole = NSRange(location: 0, length: text.length)
        let fontManager = NSFontManager.shared
        let baseSize = (typingAttributes[.font] as? NSFont)?.pointSize ?? Theme.bodyFontSize
        text.enumerateAttribute(.font, in: whole) { value, range, _ in
            let original = value as? NSFont
            let size = min(max(original?.pointSize ?? baseSize, 10), 28)
            var font: NSFont = (original?.isFixedPitch ?? false)
                ? .monospacedSystemFont(ofSize: size, weight: .regular)
                : .systemFont(ofSize: size)
            if let original {
                let traits = fontManager.traits(of: original)
                if traits.contains(.boldFontMask) { font = fontManager.convert(font, toHaveTrait: .boldFontMask) }
                if traits.contains(.italicFontMask) { font = fontManager.convert(font, toHaveTrait: .italicFontMask) }
            }
            text.addAttribute(.font, value: font, range: range)
        }
        text.removeAttribute(.backgroundColor, range: whole)
        text.removeAttribute(.shadow, range: whole)
        text.addAttribute(.foregroundColor, value: Theme.ink, range: whole)

        let target = rangeForUserTextChange
        guard target.location != NSNotFound, shouldChangeText(in: target, replacementString: text.string) else { return }
        textStorage?.replaceCharacters(in: target, with: text)
        didChangeText()
        setSelectedRange(NSRange(location: target.location + text.length, length: 0))
        scrollRangeToVisible(selectedRange())
    }

    // MARK: Formatting

    private var selectedTextRanges: [NSRange] {
        selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
    }

    /// The font at the start of the selection, or the typing font if nothing is selected.
    private var currentFont: NSFont {
        if let range = selectedTextRanges.first,
           let font = textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
            return font
        }
        return (typingAttributes[.font] as? NSFont) ?? Theme.bodyFont
    }

    /// Applies `transform` to every font in the selection (undoably), or to the
    /// typing font when there is no selection.
    private func modifyFonts(_ transform: (NSFont) -> NSFont) {
        let ranges = selectedTextRanges
        guard let storage = textStorage, !ranges.isEmpty else {
            typingAttributes[.font] = transform(currentFont)
            return
        }
        guard shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: nil) else { return }
        storage.beginEditing()
        for range in ranges {
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                storage.addAttribute(.font, value: transform((value as? NSFont) ?? Theme.bodyFont), range: subrange)
            }
        }
        storage.endEditing()
        didChangeText()
    }

    func toggleFontTrait(_ trait: NSFontTraitMask) {
        let fontManager = NSFontManager.shared
        let adding = !fontManager.traits(of: currentFont).contains(trait)
        modifyFonts { font in
            adding ? fontManager.convert(font, toHaveTrait: trait) : fontManager.convert(font, toNotHaveTrait: trait)
        }
    }

    func adjustFontSize(by delta: CGFloat) {
        modifyFonts { font in
            NSFontManager.shared.convert(font, toSize: min(max(font.pointSize + delta, 8), 72))
        }
    }

    /// Toggles an on/off style attribute such as underline or strikethrough.
    func toggleAttribute(_ key: NSAttributedString.Key) {
        let ranges = selectedTextRanges
        let isOn: Bool
        if let range = ranges.first {
            isOn = ((textStorage?.attribute(key, at: range.location, effectiveRange: nil) as? Int) ?? 0) != 0
        } else {
            isOn = ((typingAttributes[key] as? Int) ?? 0) != 0
        }
        let style = NSUnderlineStyle.single.rawValue

        guard let storage = textStorage, !ranges.isEmpty else {
            typingAttributes[key] = isOn ? nil : style
            return
        }
        guard shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: nil) else { return }
        storage.beginEditing()
        for range in ranges {
            if isOn {
                storage.removeAttribute(key, range: range)
            } else {
                storage.addAttribute(key, value: style, range: range)
            }
        }
        storage.endEditing()
        didChangeText()
    }

    func performUndo() {
        breakUndoCoalescing()
        if let undoManager, undoManager.canUndo { undoManager.undo() }
    }

    func performRedo() {
        breakUndoCoalescing()
        if let undoManager, undoManager.canRedo { undoManager.redo() }
    }
}
