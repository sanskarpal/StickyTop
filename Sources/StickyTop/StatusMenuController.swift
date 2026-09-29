import AppKit
import StickyCore

/// The menu bar icon — StickyTop's only "app window". Rebuilt on every open so
/// it always reflects the current notes.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let manager: NoteManager
    private let menu = NSMenu()

    init(manager: NoteManager) {
        self.manager = manager
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.toolTip = "StickyTop"
        updateIcon()
    }

    func updateIcon() {
        let symbol: String
        let description: String
        if manager.isHidden {
            symbol = "eye.slash"
            description = "StickyTop (notes hidden)"
        } else if manager.settings.clickThrough {
            symbol = "lock.fill"
            description = "StickyTop (notes locked)"
        } else {
            symbol = "note.text"
            description = "StickyTop"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        add("New Note", key: "n", modifiers: [.control, .option], action: #selector(newNote))
        add(manager.isHidden ? "Show All Notes" : "Hide All Notes", key: "h", modifiers: [.control, .option], action: #selector(toggleVisibility))
        add("Lock Notes (Click-Through)", key: "l", modifiers: [.control, .option], action: #selector(toggleClickThrough))
            .state = manager.settings.clickThrough ? .on : .off

        let notes = manager.notes
        if !notes.isEmpty {
            menu.addItem(.separator())
            menu.addItem(sectionHeader("Notes"))
            for note in notes {
                let item = add(note.title, action: #selector(focusNote(_:)))
                item.image = Theme.swatch(for: note.color)
                item.representedObject = note.id
                item.indentationLevel = 0
            }
        }

        menu.addItem(.separator())
        menu.addItem(trashItem())
        add("Gather Notes Here", action: #selector(gatherNotes))

        menu.addItem(.separator())
        menu.addItem(neverInTheWayItem())
        menu.addItem(nudgesItem())
        add("Float Above Everything", action: #selector(toggleFloatAboveEverything))
            .state = manager.settings.floatAboveEverything ? .on : .off
        let login = add("Launch at Login", action: #selector(toggleLaunchAtLogin))
        login.state = LoginItem.isAvailable && LoginItem.isEnabled ? .on : .off
        login.isEnabled = LoginItem.isAvailable
        if !LoginItem.isAvailable { login.toolTip = "Available when running the installed StickyTop.app" }
        add("Show Notes Folder", action: #selector(revealDataFolder))

        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let about = menu.addItem(withTitle: "StickyTop \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        add("Quit StickyTop", key: "q", modifiers: .command, action: #selector(quit))
    }

    // MARK: Building

    @discardableResult
    private func add(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], action: Selector) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return .sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func trashItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Recently Deleted", action: nil, keyEquivalent: "")
        let trash = manager.trash
        guard !trash.isEmpty else {
            item.isEnabled = false
            return item
        }
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        for note in trash {
            let restore = submenu.addItem(withTitle: note.title, action: #selector(restoreNote(_:)), keyEquivalent: "")
            restore.target = self
            restore.image = Theme.swatch(for: note.color)
            restore.representedObject = note.id
            restore.toolTip = "Edited \(formatter.localizedString(for: note.modifiedAt, relativeTo: Date()))"
        }
        submenu.addItem(.separator())
        let empty = submenu.addItem(withTitle: "Empty Recently Deleted", action: #selector(emptyTrash), keyEquivalent: "")
        empty.target = self
        item.submenu = submenu
        return item
    }

    private func neverInTheWayItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Never in the Way", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let settings = manager.settings

        let dodge: NSMenuItem
        if CaretTracker.isTrusted {
            dodge = submenu.addItem(withTitle: "Dodge Text Cursor", action: #selector(toggleCaretDodge), keyEquivalent: "")
            dodge.state = settings.dodgeCaret ? .on : .off
            dodge.toolTip = "Notes slide off the line you're typing on in other apps, then come back."
        } else {
            dodge = submenu.addItem(withTitle: "Dodge Text Cursor — Allow Access…", action: #selector(toggleCaretDodge), keyEquivalent: "")
            dodge.toolTip = "Needs Accessibility access to see where the text cursor is. StickyTop only reads the cursor position."
            // After an update, macOS keeps showing the old grant as "on" but it no
            // longer matches the new app, and toggling it doesn't help.
            for line in ["Already on in System Settings? After an update,", "remove StickyTop there (−) and add it again (+)."] {
                submenu.addItem(withTitle: line, action: nil, keyEquivalent: "").isEnabled = false
            }
        }
        dodge.target = self

        let drag = submenu.addItem(withTitle: "See Through While Dragging", action: #selector(toggleDragThrough), keyEquivalent: "")
        drag.state = settings.dragThrough ? .on : .off
        drag.target = self
        drag.toolTip = "Files, windows and selections dragged across a note pass straight through it."

        let peek = submenu.addItem(withTitle: "Hold ⌃⌥ to Peek Through", action: #selector(togglePeekThrough), keyEquivalent: "")
        peek.state = settings.peekThrough ? .on : .off
        peek.target = self
        peek.toolTip = "While you hold Control-Option, every note turns see-through and clicks pass through."

        item.submenu = submenu
        return item
    }

    private func nudgesItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Nudges", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let nudges = manager.nudges
        let freshCount = manager.notes.filter(\.keepFresh).count

        if freshCount == 0 {
            submenu.addItem(withTitle: "No notes kept fresh yet —", action: nil, keyEquivalent: "").isEnabled = false
            submenu.addItem(withTitle: "choose Keep Fresh in a note's ••• menu.", action: nil, keyEquivalent: "").isEnabled = false
            submenu.addItem(.separator())
        }

        let now = add(to: submenu, "Nudge Fresh Notes Now", action: #selector(nudgeNow))
        now.isEnabled = freshCount > 0 && !manager.isHidden

        if nudges.isPaused(), let until = nudges.pausedUntil {
            let time = until.formatted(date: .omitted, time: .shortened)
            add(to: submenu, "Resume Nudges (paused until \(time))", action: #selector(resumeNudges))
        } else {
            add(to: submenu, "Pause Nudges for 1 Hour", action: #selector(pauseNudges))
        }

        submenu.addItem(.separator())
        let reword = add(to: submenu, "Reword with Apple Intelligence", action: #selector(toggleRewording))
        if Rephraser.isAvailable {
            reword.state = manager.settings.rewordWithAI ? .on : .off
            reword.toolTip = "Nudges reword your reminder on-device (marked ✦), so it reads freshly each time. Your note itself is never changed. A small model can drift slightly; your own words stay visible above the card."
        } else {
            reword.isEnabled = false
            submenu.addItem(withTitle: Rephraser.unavailableReason, action: nil, keyEquivalent: "").isEnabled = false
        }

        item.submenu = submenu
        return item
    }

    @discardableResult
    private func add(to submenu: NSMenu, _ title: String, action: Selector) -> NSMenuItem {
        let item = submenu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func nudgeNow() { manager.nudges.nudgeNow() }
    @objc private func pauseNudges() { manager.nudges.pause(for: 3600) }
    @objc private func resumeNudges() { manager.nudges.resume() }
    @objc private func toggleRewording() {
        manager.settings.rewordWithAI.toggle()
        manager.nudges.prepareRewordings()
    }

    @objc private func toggleCaretDodge() {
        if CaretTracker.isTrusted && manager.settings.dodgeCaret {
            manager.dodge.disableCaretDodge()
        } else {
            manager.dodge.enableCaretDodge()
        }
    }

    @objc private func toggleDragThrough() {
        manager.settings.dragThrough.toggle()
        manager.dodge.refresh()
    }

    @objc private func togglePeekThrough() {
        manager.settings.peekThrough.toggle()
        manager.dodge.refresh()
    }

    @objc private func newNote() { manager.createNote() }
    @objc private func toggleVisibility() { manager.toggleVisibility() }
    @objc private func toggleClickThrough() { manager.toggleClickThrough() }
    @objc private func gatherNotes() { manager.gatherNotes() }
    @objc private func emptyTrash() { manager.emptyTrash() }

    @objc private func focusNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        manager.focus(noteID: id)
    }

    @objc private func restoreNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        manager.restore(noteID: id)
    }

    @objc private func toggleFloatAboveEverything() {
        manager.setFloatAboveEverything(!manager.settings.floatAboveEverything)
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func revealDataFolder() {
        manager.saveNow()
        NSWorkspace.shared.activateFileViewerSelecting([manager.store.fileURL])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
