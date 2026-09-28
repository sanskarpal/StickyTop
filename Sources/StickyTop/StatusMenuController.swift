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

    // MARK: Actions

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
