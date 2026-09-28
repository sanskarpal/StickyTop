import AppKit
import StickyCore

/// User preferences (UserDefaults-backed).
final class Settings {
    private enum Key {
        static let floatAboveEverything = "floatAboveEverything"
        static let clickThrough = "clickThrough"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.floatAboveEverything: true, Key.clickThrough: false])
    }

    /// Notes sit at status-bar level (above every app window, including other
    /// apps' floating palettes) instead of the ordinary floating level.
    var floatAboveEverything: Bool {
        get { defaults.bool(forKey: Key.floatAboveEverything) }
        set { defaults.set(newValue, forKey: Key.floatAboveEverything) }
    }

    /// Notes ignore the mouse so clicks land on whatever is underneath.
    var clickThrough: Bool {
        get { defaults.bool(forKey: Key.clickThrough) }
        set { defaults.set(newValue, forKey: Key.clickThrough) }
    }
}

/// Owns every note window, the document on disk, and the global note actions.
@MainActor
final class NoteManager {
    let settings = Settings()
    let store: NoteStore
    /// Called whenever something the status menu icon reflects changes.
    var onStateChange: (() -> Void)?

    private(set) var isHidden = false
    private var document = NotesDocument()
    private var controllers: [NoteWindowController] = []
    private var pendingSave: Task<Void, Never>?

    init(store: NoteStore = NoteStore()) {
        self.store = store
    }

    var notes: [Note] { controllers.map(\.note) }
    var trash: [Note] { document.trash }

    var windowLevel: NSWindow.Level {
        settings.floatAboveEverything ? .statusBar : .floating
    }

    // MARK: Lifecycle

    func start() {
        let (loaded, status) = store.load()
        document = loaded
        if status == .fresh {
            document.notes.append(makeWelcomeNote())
        }
        if status == .corrupt {
            NSLog("StickyTop: notes.json was unreadable; it was moved aside in \(store.directory.path)")
        }
        for note in document.notes {
            open(note)
        }
        keepNotesOnScreen()
        if status != .loaded { saveNow() }
    }

    @discardableResult
    private func open(_ note: Note) -> NoteWindowController {
        let controller = NoteWindowController(note: note, manager: self)
        controller.panel.level = windowLevel
        controller.panel.ignoresMouseEvents = settings.clickThrough
        controllers.append(controller)
        if !isHidden { controller.show() }
        return controller
    }

    // MARK: Creating & deleting

    /// Creates a note under the pointer, or cascaded from `source` (⌘N in a note).
    @discardableResult
    func createNote(cascadingFrom source: NoteWindowController? = nil) -> NoteWindowController {
        if isHidden { showAll() }
        let frame: CGRect
        let color: NoteColor
        if let source {
            let visible = (source.panel.screen ?? NSScreen.main)?.visibleFrame ?? source.note.frame
            frame = NoteGeometry.cascaded(from: source.note.frame, in: visible)
            color = source.note.color
        } else {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: Note.defaultSize)
            frame = NoteGeometry.placement(for: Note.defaultSize, anchoredAt: mouse, in: visible)
            color = .yellow
        }
        let controller = open(Note(frame: frame, color: color))
        controller.focus()
        saveSoon()
        return controller
    }

    /// Deletes a note. Notes with text go to Recently Deleted; blank ones vanish.
    func delete(_ controller: NoteWindowController) {
        controller.syncTextToModel()
        controllers.removeAll { $0 === controller }
        controller.close()
        document.notes.removeAll { $0.id == controller.id }
        if !controller.note.isBlank {
            document.moveToTrash(controller.note)
        }
        saveNow()
    }

    func restore(noteID: UUID) {
        guard var note = document.takeFromTrash(id: noteID) else { return }
        note.frame = NoteGeometry.clamp(note.frame, to: screenAreas)
        if isHidden { showAll() }
        open(note).focus()
        saveNow()
    }

    func emptyTrash() {
        document.trash.removeAll()
        saveNow()
    }

    // MARK: Visibility

    func showAll() {
        isHidden = false
        controllers.forEach { $0.show() }
        onStateChange?()
    }

    func hideAll() {
        isHidden = true
        controllers.forEach { $0.panel.orderOut(nil) }
        onStateChange?()
    }

    func toggleVisibility() {
        isHidden ? showAll() : hideAll()
    }

    func focus(noteID: UUID) {
        guard let controller = controllers.first(where: { $0.id == noteID }) else { return }
        if isHidden { showAll() }
        let frame = controller.panel.frame
        let reachable = NoteGeometry.clamp(frame, to: screenAreas)
        if reachable != frame { controller.setDisplayedFrame(reachable) }
        controller.focus()
    }

    /// Re-stacks visible notes above everything (keeping their relative order).
    /// Cheap insurance after Space switches and full-screen transitions.
    func reassertStacking() {
        guard !isHidden else { return }
        let ours = Set(controllers.map { $0.panel.windowNumber })
        let frontToBack = (NSWindow.windowNumbers(options: []) ?? []).map(\.intValue).filter(ours.contains)
        let ordered = frontToBack.compactMap { number in controllers.first { $0.panel.windowNumber == number } }
        let rest = controllers.filter { controller in !ordered.contains { $0 === controller } }
        for controller in (ordered + rest).reversed() {
            controller.panel.orderFrontRegardless()
        }
    }

    // MARK: Preferences

    func setFloatAboveEverything(_ enabled: Bool) {
        settings.floatAboveEverything = enabled
        controllers.forEach { $0.panel.level = windowLevel }
    }

    func setClickThrough(_ enabled: Bool) {
        settings.clickThrough = enabled
        controllers.forEach { $0.panel.ignoresMouseEvents = enabled }
        onStateChange?()
    }

    func toggleClickThrough() {
        setClickThrough(!settings.clickThrough)
    }

    // MARK: Screens

    private var screenAreas: [ScreenArea] {
        NSScreen.screens.map { ScreenArea(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    /// Pulls back any note stranded off-screen (e.g. after unplugging a display).
    func keepNotesOnScreen() {
        let screens = screenAreas
        for controller in controllers {
            let frame = controller.panel.frame
            let reachable = NoteGeometry.clamp(frame, to: screens)
            if reachable != frame { controller.setDisplayedFrame(reachable) }
        }
        saveSoon()
    }

    /// Cascades every note onto the screen under the pointer.
    func gatherNotes() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let frames = NoteGeometry.gathered(controllers.map { $0.panel.frame }, in: screen.visibleFrame)
        for (controller, frame) in zip(controllers, frames) {
            controller.setDisplayedFrame(frame, animate: true)
        }
        if isHidden { showAll() }
        saveSoon()
    }

    // MARK: Saving

    /// Debounced save for high-frequency changes (typing, dragging).
    func saveSoon() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        controllers.forEach { $0.syncTextToModel() }
        document.notes = controllers.map(\.note)
        do {
            try store.save(document)
        } catch {
            NSLog("StickyTop: failed to save notes: \(error.localizedDescription)")
        }
    }

    // MARK: Development

    /// Writes each note as PNG (plain, then as it looks under the pointer).
    func writeSnapshots(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, controller) in controllers.enumerated() {
            controller.panel.makeFirstResponder(nil) // no caret in the picture
            let name = String(format: "note-%02d", index + 1)
            try? controller.snapshotPNG()?.write(to: directory.appendingPathComponent("\(name).png"))
            controller.setHovering(true)
            try? controller.snapshotPNG()?.write(to: directory.appendingPathComponent("\(name)-hover.png"))
            controller.setHovering(false)
        }
    }

    // MARK: Welcome

    private func makeWelcomeNote() -> Note {
        let bold = NSFont.boldSystemFont(ofSize: 15)
        let text = NSMutableAttributedString(
            string: "Welcome to StickyTop\n",
            attributes: [.font: bold, .foregroundColor: Theme.ink]
        )
        let body = """
        This note floats above every app, every desktop and full-screen windows.

        ⌃⌥N  new note from anywhere
        ⌃⌥H  hide / show all notes
        ⌃⌥L  lock notes (clicks pass through)

        Double-click the top bar to collapse.
        ⌘1–⌘6 color · ⌥⌘T opacity · ⌘B ⌘I ⌘U
        ⌘W deletes (restore it from the menu bar).
        """
        text.append(NSAttributedString(
            string: body,
            attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Theme.ink]
        ))

        let size = CGSize(width: 290, height: 240)
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NoteGeometry.fit(
            CGRect(x: visible.maxX - size.width - 32, y: visible.maxY - size.height - 32, width: size.width, height: size.height),
            inside: visible
        )
        return Note(richText: RichText.archive(text), plainText: text.string, frame: frame, color: .yellow)
    }
}
