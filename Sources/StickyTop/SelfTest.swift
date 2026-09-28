#if DEBUG
import AppKit
import StickyCore

/// In-process integration test (debug builds only):
///
///     swift build && .build/debug/StickyTop --data-dir /tmp/sticky-selftest --self-test
///
/// Drives real note windows with synthesized key equivalents and checks the
/// model, the window state and what lands on disk. Exits 0 on success.
@MainActor
enum SelfTest {
    private static var failures = 0

    static func run(manager: NoteManager) async {
        /// Lets the run loop turn, like real input: closes undo groups, settles key-window state.
        func settle() async {
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        func fontAtStart(_ controller: NoteWindowController) -> NSFont? {
            guard let storage = controller.textView.textStorage, storage.length > 0 else { return nil }
            return storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        }
        func check(_ condition: Bool, _ label: String) {
            print(condition ? "  ✔ \(label)" : "  ✘ \(label)")
            if !condition { failures += 1 }
        }
        func press(_ key: String, _ flags: NSEvent.ModifierFlags, in controller: NoteWindowController) -> Bool {
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: controller.panel.windowNumber, context: nil,
                characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0
            ) else { return false }
            return controller.panel.performKeyEquivalent(with: event)
        }

        print("StickyTop self-test")
        let startCount = manager.notes.count

        // Hand activation to Finder so StickyTop starts inactive — like when you're
        // working in another app and summon a note.
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            if #available(macOS 14.0, *) {
                finder.activate(from: .current, options: [])
            } else {
                finder.activate(options: [])
            }
        }
        try? await Task.sleep(nanoseconds: 600_000_000)
        let myPID = ProcessInfo.processInfo.processIdentifier
        let frontmostBefore = NSWorkspace.shared.frontmostApplication

        // Floating configuration
        let note = manager.createNote()
        let panel = note.panel
        await settle()
        check(panel.level == .statusBar, "note floats at status-bar level")
        check(panel.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary]), "note joins all Spaces and full-screen Spaces")
        check(!panel.hidesOnDeactivate, "note does not hide when another app is active")
        check(panel.styleMask.contains(.nonactivatingPanel), "note never activates the app")
        check(panel.isKeyWindow, "new note takes keyboard focus")
        // The frontmost app owns the menu bar and its full-screen Space; it must not change.
        // (AppKit reports NSApp.isActive while a non-activating panel is key; that's expected.)
        let frontmostAfter = NSWorkspace.shared.frontmostApplication
        check(frontmostBefore?.processIdentifier != myPID && frontmostAfter?.processIdentifier == frontmostBefore?.processIdentifier,
              "…while \(frontmostAfter?.localizedName ?? "the other app") stays the frontmost app")
        check(panel.firstResponder === note.textView, "caret is in the new note")

        // Typing and formatting
        note.textView.insertText("Hello floating world", replacementRange: NSRange(location: NSNotFound, length: 0))
        check(note.note.plainText == "Hello floating world", "typed text reaches the model")
        await settle()
        check(press("a", .command, in: note), "⌘A handled")
        check(press("b", .command, in: note), "⌘B handled")
        check(fontAtStart(note).map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "⌘B makes the selection bold")
        await settle()
        check(press("z", .command, in: note), "⌘Z handled")
        check(note.textView.string == "Hello floating world", "⌘Z keeps the typed text…")
        check(fontAtStart(note).map { !NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "…and undoes only the bold")
        await settle()
        _ = press("a", .command, in: note)
        _ = press("i", .command, in: note)
        _ = press("=", .command, in: note)
        let styledFont = fontAtStart(note)
        check(styledFont.map { NSFontManager.shared.traits(of: $0).contains(.italicFontMask) && $0.pointSize == Theme.bodyFontSize + 1 } == true,
              "⌘I italicizes and ⌘= enlarges")

        // Appearance
        _ = press("2", .command, in: note)
        check(note.note.color == .blue, "⌘2 turns the note blue")
        _ = press("t", [.command, .option], in: note)
        try? await Task.sleep(nanoseconds: 400_000_000) // fade animation
        check(note.note.opacity == 0.85 && abs(panel.alphaValue - 0.85) < 0.01, "⌥⌘T makes the note translucent")

        // Collapse keeps the top edge and restores the height
        await settle()
        let expanded = panel.frame
        _ = press("m", .command, in: note)
        check(note.note.isCollapsed && panel.frame.height == NoteGeometry.headerHeight && panel.frame.maxY == expanded.maxY,
              "⌘M collapses to the drag bar, top edge fixed")
        _ = press("m", .command, in: note)
        check(!note.note.isCollapsed && panel.frame.height == expanded.height, "⌘M expands back to full height")

        // New note, delete, trash, restore
        _ = press("n", .command, in: note)
        await settle()
        check(manager.notes.count == startCount + 2, "⌘N opens another note")
        if let second = manager.notes.last.flatMap({ last in last.id == note.id ? nil : last }) {
            check(second.frame.minX == note.note.frame.minX + NoteGeometry.cascadeOffset || second.frame.minX < note.note.frame.minX,
                  "new note cascades from the current one")
            check(second.color == .blue, "new note inherits the color")
        }
        let trashBefore = manager.trash.count
        if let blank = NSApp.windows.compactMap({ $0 as? NotePanel }).first(where: { $0.isKeyWindow }),
           let handler = blank.keyEquivalentHandler,
           let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                        windowNumber: blank.windowNumber, context: nil, characters: "w",
                                        charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 0) {
            _ = handler(event)
        }
        check(manager.notes.count == startCount + 1 && manager.trash.count == trashBefore, "⌘W on a blank note discards it")
        _ = press("w", .command, in: note)
        check(manager.notes.count == startCount && manager.trash.first?.id == note.id, "⌘W on a written note moves it to Recently Deleted")
        manager.restore(noteID: note.id)
        check(manager.notes.contains { $0.id == note.id } && !manager.trash.contains { $0.id == note.id }, "restore brings it back")

        // Global toggles (only live notes; closed panels linger in NSApp.windows until released)
        await settle()
        func livePanels() -> [NotePanel] { NSApp.windows.compactMap { $0 as? NotePanel }.filter(\.isVisible) }
        manager.hideAll()
        check(NSApp.windows.compactMap { $0 as? NotePanel }.allSatisfy { !$0.isVisible }, "hide all hides every note")
        manager.showAll()
        check(livePanels().count == manager.notes.count, "show all brings them back")
        manager.setClickThrough(true)
        check(livePanels().allSatisfy(\.ignoresMouseEvents), "lock makes notes click-through")
        manager.setClickThrough(false)
        check(livePanels().allSatisfy { !$0.ignoresMouseEvents }, "unlock makes them clickable again")
        manager.setFloatAboveEverything(false)
        check(livePanels().allSatisfy { $0.level == .floating }, "gentle mode uses the floating level")
        manager.setFloatAboveEverything(true)

        // Deleted notes are released, not leaked.
        weak var weakController: NoteWindowController?
        do {
            let doomed = manager.createNote()
            weakController = doomed
            await settle()
            doomed.delete()
        }
        await settle()
        await settle()
        // (AppKit itself may hold a closed on-screen window a little longer.)
        check(weakController == nil, "deleted note's controller is freed")

        // Persistence
        manager.saveNow()
        let (onDisk, status) = NoteStore(directory: manager.store.directory).load()
        let saved = onDisk.notes.first { $0.id == note.id }
        check(status == .loaded && onDisk.notes.count == manager.notes.count, "notes are saved to disk")
        check(saved?.color == .blue && saved?.opacity == 0.85 && saved?.plainText == "Hello floating world", "saved note keeps text, color and opacity")
        let reloaded = saved.flatMap { RichText.unarchive($0.richText) }
        let reloadedFont = reloaded?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        check(reloadedFont.map { NSFontManager.shared.traits(of: $0).contains(.italicFontMask) } == true, "rich formatting survives a reload")

        print(failures == 0 ? "PASS: all self-test checks passed" : "FAIL: \(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
