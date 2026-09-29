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
        // Drive "never in the way" with scripted input instead of the real pointer.
        manager.dodge.automaticTicks = false
        manager.settings.dodgeCaret = true
        manager.settings.dragThrough = true
        manager.settings.peekThrough = true

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
        if let blank = manager.visibleControllers.last, blank !== note {
            _ = press("w", .command, in: blank)
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

        // Never in the way
        await neverInTheWay(manager: manager, keyNote: note, check: check, settle: settle)

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

    private static func neverInTheWay(
        manager: NoteManager,
        keyNote: NoteWindowController,
        check: (Bool, String) -> Void,
        settle: () async -> Void
    ) async {
        typealias Input = DodgeCoordinator.Input
        let dodge = manager.dodge
        func idle(_ mouse: CGPoint) -> Input {
            Input(caret: nil, mouse: mouse, primaryButtonDown: false, modifiers: [])
        }
        func animations() async { try? await Task.sleep(nanoseconds: 400_000_000) }

        // A note on the half of the screen away from the real pointer (so hover
        // can't interfere), and not the key window (typing in it pauses dodging).
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let pointer = NSEvent.mouseLocation
        let homeX = pointer.x > visible.midX ? visible.minX + 80 : visible.maxX - 340
        let home = CGRect(x: homeX, y: visible.midY - 110, width: 260, height: 220)
        let outside = CGPoint(x: home.maxX + 200 > visible.maxX ? home.minX - 150 : home.maxX + 150, y: home.midY)
        let note = manager.createNote()
        note.setDisplayedFrame(home)
        keyNote.focus()
        await settle()
        check(!note.panel.isKeyWindow && note.homeDisplayedFrame == home, "dodge test note placed (not key)")

        // Caret lands on the note's bottom line in "another app".
        let caret = CGRect(x: home.midX, y: home.minY + 20, width: 2, height: 18)
        dodge.inputOverride = Input(caret: caret, mouse: outside, primaryButtonDown: false, modifiers: [])
        dodge.tick(now: 100)
        await animations()
        check(note.dodgedFrame != nil && !NoteDodge.isObstructing(note.panel.frame, caret: caret),
              "note slides clear of the text cursor")
        check(note.panel.frame.size == home.size && visible.contains(note.panel.frame), "…keeping its size and staying on screen")
        check(note.homeDisplayedFrame == home, "…without forgetting where it lives")

        // Typing continues along the same line: no bouncing.
        let dodgedAt = note.panel.frame
        dodge.inputOverride?.caret = caret.offsetBy(dx: 40, dy: 0)
        dodge.tick(now: 100.3)
        await animations()
        check(note.panel.frame == dodgedAt, "stays put while you keep typing on that line")

        // Caret hops just outside home's zone and back (typing along its edge): no ping-pong.
        dodge.inputOverride?.caret = CGRect(x: home.midX, y: home.minY - 60, width: 2, height: 18)
        dodge.tick(now: 100.5)
        dodge.inputOverride?.caret = caret
        dodge.tick(now: 100.6)
        await animations()
        check(note.panel.frame == dodgedAt, "a brief hop out of the zone doesn't send it home and back")

        // Caret leaves: wait a beat, then go home.
        dodge.inputOverride = idle(outside)
        dodge.tick(now: 100.8)
        dodge.tick(now: 101.5)
        check(note.dodgedFrame != nil, "waits a full second after the cursor leaves before returning")
        dodge.tick(now: 101.9)
        await animations()
        check(note.dodgedFrame == nil && note.panel.frame == home, "returns home once the cursor is gone")
        manager.saveNow()
        let saved = NoteStore(directory: manager.store.directory).load().document.notes.first { $0.id == note.id }
        check(saved?.frame == home, "temporary dodges are never saved as the note's position")

        // User drags the note while it's dodged: that spot becomes home.
        dodge.inputOverride = Input(caret: caret, mouse: outside, primaryButtonDown: false, modifiers: [])
        dodge.tick(now: 110)
        await animations()
        let userSpot = CGPoint(x: home.minX, y: home.minY - 40)
        note.panel.setFrameOrigin(userSpot)
        await settle()
        check(note.dodgedFrame == nil && note.homeDisplayedFrame.origin == userSpot, "moving a dodged note by hand makes it the new home")
        dodge.inputOverride = idle(outside)
        dodge.tick(now: 120)
        note.setDisplayedFrame(home)

        // Pointer actively on the note: leave it be. Parked pointer: dodge anyway.
        let onNote = CGPoint(x: home.midX, y: home.maxY - 40)
        dodge.inputOverride = Input(caret: nil, mouse: onNote.applying(.init(translationX: -5, y: 0)), primaryButtonDown: false, modifiers: [])
        dodge.tick(now: 124)
        dodge.inputOverride = Input(caret: caret, mouse: onNote, primaryButtonDown: false, modifiers: [])
        dodge.tick(now: 124.1)
        await animations()
        check(note.dodgedFrame == nil, "a note you're pointing at (pointer just moved) isn't pulled away")
        dodge.tick(now: 126)
        await animations()
        check(note.dodgedFrame != nil, "a pointer merely parked on the note doesn't block dodging")
        dodge.inputOverride = idle(outside)
        dodge.tick(now: 128)
        await animations()
        note.setDisplayedFrame(home)

        // No room to escape (note fills the screen): fade in place instead.
        note.setDisplayedFrame(visible)
        dodge.inputOverride = Input(caret: CGRect(x: visible.midX, y: visible.midY, width: 2, height: 18),
                                    mouse: outside, primaryButtonDown: false, modifiers: [])
        dodge.tick(now: 130)
        await animations()
        check(note.isGhosted && note.panel.alphaValue < 0.2 && note.panel.ignoresMouseEvents,
              "a note too big to move fades out of the way instead")
        dodge.inputOverride = idle(outside)
        dodge.tick(now: 131.5)
        dodge.tick(now: 132.6)
        await animations()
        check(!note.isGhosted && note.panel.alphaValue > 0.9 && !note.panel.ignoresMouseEvents, "…and comes back when the cursor leaves")
        note.setDisplayedFrame(home)

        // Dragging something from another app across the note.
        dodge.mouseDown(at: outside, onNote: false)
        dodge.inputOverride = Input(caret: nil, mouse: CGPoint(x: home.midX, y: home.midY), primaryButtonDown: true, modifiers: [])
        dodge.tick(now: 140)
        check(note.isGhosted && note.panel.ignoresMouseEvents, "a drag from elsewhere passes through the note")
        dodge.inputOverride?.mouse = outside
        dodge.tick(now: 140.1)
        check(!note.isGhosted, "…which turns solid again once the drag moves on")
        dodge.inputOverride = idle(outside)
        dodge.tick(now: 140.2)

        // Dragging inside the note (selecting its text) must not ghost it.
        dodge.mouseDown(at: CGPoint(x: home.midX, y: home.midY), onNote: true)
        dodge.inputOverride = Input(caret: nil, mouse: CGPoint(x: home.midX, y: home.midY), primaryButtonDown: true, modifiers: [])
        dodge.tick(now: 150)
        check(!note.isGhosted, "dragging within a note keeps it solid")
        dodge.inputOverride = idle(outside)
        dodge.tick(now: 150.1)

        // Hold ⌃⌥ to peek through every note.
        dodge.inputOverride = Input(caret: nil, mouse: outside, primaryButtonDown: false, modifiers: [.control, .option])
        dodge.tick(now: 160)
        check(!note.isGhosted, "a quick ⌃⌥ tap (e.g. a hotkey) doesn't flicker notes")
        dodge.tick(now: 160.35)
        check(manager.visibleControllers.allSatisfy { $0.isGhosted && $0.panel.ignoresMouseEvents }, "holding ⌃⌥ makes every note see-through and click-through")
        dodge.inputOverride?.modifiers = []
        dodge.tick(now: 160.4)
        check(manager.visibleControllers.allSatisfy { !$0.isGhosted && !$0.panel.ignoresMouseEvents }, "releasing ⌃⌥ brings them back")
        dodge.inputOverride?.modifiers = [.control, .option, .command]
        dodge.tick(now: 161)
        dodge.tick(now: 162)
        check(!note.isGhosted, "⌃⌥⌘ (other shortcuts) doesn't peek")

        // Lock (click-through) survives a peek.
        manager.setClickThrough(true)
        dodge.inputOverride?.modifiers = [.control, .option]
        dodge.tick(now: 170)
        dodge.tick(now: 170.5)
        dodge.inputOverride?.modifiers = []
        dodge.tick(now: 170.6)
        check(note.panel.ignoresMouseEvents && !note.isGhosted, "locked notes stay click-through after a peek")
        manager.setClickThrough(false)
        check(!note.panel.ignoresMouseEvents, "unlocking restores clicks")

        // Turning the feature off mid-slide still lands the note at home.
        dodge.inputOverride = Input(caret: caret, mouse: outside, primaryButtonDown: false, modifiers: [])
        dodge.tick(now: 175)
        dodge.disableCaretDodge() // while the 0.18 s slide is still running
        await animations()
        check(note.panel.frame == home, "switching off mid-slide still lands the note at home")
        manager.settings.dodgeCaret = true
        dodge.inputOverride = idle(outside)
        dodge.tick(now: 177)

        // Turning the feature off drops any dodge immediately.
        dodge.inputOverride = Input(caret: caret, mouse: outside, primaryButtonDown: false, modifiers: [])
        dodge.tick(now: 180)
        await animations()
        check(note.dodgedFrame != nil, "(dodged before disabling)")
        dodge.disableCaretDodge()
        check(note.dodgedFrame == nil && note.panel.frame == home, "turning Dodge Text Cursor off puts notes straight back")
        manager.settings.dodgeCaret = true

        dodge.inputOverride = nil
        note.delete()
    }
}
#endif
