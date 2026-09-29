import AppKit

/// The window behind every note, configured to stay visible no matter what:
///
/// * `.nonactivatingPanel` — clicking or typing in a note never activates
///   StickyTop, so the app you're using keeps its menu bar and full-screen Space.
/// * `level` (set by `NoteManager`) — `.statusBar` sits above every normal and
///   floating app window; `.floating` is the gentler Stickies-style option.
/// * `.canJoinAllSpaces` — present on every desktop/Space at once.
/// * `.fullScreenAuxiliary` — allowed into other apps' full-screen Spaces. This
///   only works because the app is an agent (`LSUIElement` / `.accessory`).
/// * `.stationary` — unaffected by Mission Control / Show Desktop.
/// * `hidesOnDeactivate = false` — panels hide on app switch by default; not ours.
final class NotePanel: NSPanel {
    /// Gives the note first crack at ⌘-shortcuts. The app is usually not
    /// active, so the main menu can't be relied on to route them.
    var keyEquivalentHandler: ((NSEvent) -> Bool)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = true
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        // Paper stays paper in Dark Mode (text, caret, scrollers).
        appearance = NSAppearance(named: .aqua)
    }

    /// Set while StickyTop focuses the note on purpose (new note, restore…).
    private var focusRequested = false

    /// Takes keyboard focus deliberately. The only programmatic way a note becomes key.
    func makeKeyOnPurpose() {
        focusRequested = true
        makeKey()
        focusRequested = false
    }

    /// A note takes keyboard focus only when you click it or StickyTop focuses it
    /// on purpose — never on AppKit's own initiative (e.g. while the app launches
    /// at login), which would silently send your typing into a note.
    override var canBecomeKey: Bool {
        if isKeyWindow || focusRequested { return true }
        guard let event = NSApp.currentEvent else { return false }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return event.windowNumber == windowNumber
        default:
            return false
        }
    }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}
