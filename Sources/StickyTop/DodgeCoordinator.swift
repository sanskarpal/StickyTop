import AppKit
import StickyCore

/// "Always on top, never in the way." Watches the text caret, the pointer and
/// the modifier keys, and tells each note when to slide aside or turn see-through:
///
/// * Dodge text cursor — a note slides clear of the line you're typing on in
///   another app, then returns home. Needs Accessibility access.
/// * See-through while dragging — a drag that started outside the notes
///   (file, window, text selection) passes straight through them.
/// * Hold ⌃⌥ to peek — every note turns transparent and click-through.
@MainActor
final class DodgeCoordinator {
    /// A snapshot of everything the coordinator reacts to.
    struct Input {
        var caret: CGRect?
        var mouse: CGPoint
        var primaryButtonDown: Bool
        var modifiers: NSEvent.ModifierFlags
    }

    static let peekKeys: NSEvent.ModifierFlags = [.control, .option]
    /// A pointer that moved this recently counts as "in use".
    static let pointerActiveWindow: TimeInterval = 1.5
    /// Holding the keys this long counts as a peek (quick ⌃⌥ hotkeys don't flicker notes).
    static let peekHoldDelay: TimeInterval = 0.3

    /// Tests inject input here instead of reading the real caret and pointer.
    var inputOverride: Input?
    /// Tests drive `tick(now:)` themselves.
    var automaticTicks = true {
        didSet { refresh() }
    }
    /// Called when Accessibility access changes, so the menu can refresh.
    var onTrustChange: (() -> Void)?

    private unowned let manager: NoteManager
    private let caretTracker = CaretTracker()
    private var timer: Timer?
    private var mouseMonitors: [Any] = []
    private var dragStartedOutsideNotes = false
    private var peekHeldSince: TimeInterval?
    private var lastMouse: CGPoint?
    private var lastPointerMove: TimeInterval = -.infinity
    private var trustPoll: Timer?

    init(manager: NoteManager) {
        self.manager = manager
    }

    /// Caret dodging is on and has a caret source (Accessibility, or test input).
    var isCaretDodgeActive: Bool {
        manager.settings.dodgeCaret && (CaretTracker.isTrusted || inputOverride != nil)
    }

    // MARK: Lifecycle

    func start() {
        installMouseMonitors()
        refresh()
    }

    /// Starts or stops the tick and caret polling to match settings and visibility.
    func refresh() {
        let anyVisible = !manager.visibleControllers.isEmpty
        let settings = manager.settings
        let wantsTick = automaticTicks && anyVisible
            && (isCaretDodgeActive || settings.dragThrough || settings.peekThrough)

        if wantsTick, timer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.03
            RunLoop.main.add(timer, forMode: .default)
            self.timer = timer
        } else if !wantsTick, let timer {
            timer.invalidate()
            self.timer = nil
            if automaticTicks { manager.visibleControllers.forEach { $0.clearDodge() } }
        }

        if anyVisible && manager.settings.dodgeCaret && CaretTracker.isTrusted {
            caretTracker.start()
        } else if caretTracker.isRunning {
            caretTracker.stop()
        }
        if !isCaretDodgeActive {
            manager.visibleControllers.forEach { $0.endCaretDodge() }
        }
    }

    /// Turns caret dodging on, asking for Accessibility access if needed.
    func enableCaretDodge() {
        manager.settings.dodgeCaret = true
        if !CaretTracker.isTrusted {
            CaretTracker.requestTrust()
            waitForTrust()
        }
        refresh()
    }

    func disableCaretDodge() {
        manager.settings.dodgeCaret = false
        refresh()
    }

    /// Polls for the user flipping the switch in System Settings (no callback exists).
    private func waitForTrust() {
        trustPoll?.invalidate()
        var remaining = 180
        let poll = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                remaining -= 1
                if CaretTracker.isTrusted || remaining <= 0 {
                    timer.invalidate()
                    self?.refresh()
                    self?.onTrustChange?()
                }
            }
        }
        RunLoop.main.add(poll, forMode: .common)
        trustPoll = poll
    }

    // MARK: Input

    /// Records where a click began: on a note (you're using the note) or
    /// elsewhere (you're dragging something that should pass through notes).
    func mouseDown(at point: CGPoint, onNote: Bool) {
        dragStartedOutsideNotes = !onNote
    }

    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        // Clicks in other apps (mouse monitoring needs no special permission).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown(at: NSEvent.mouseLocation, onNote: false) }
        }) {
            mouseMonitors.append(global)
        }
        // Clicks on our own windows.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                self?.mouseDown(at: NSEvent.mouseLocation, onNote: event.window is NotePanel)
            }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func readInput() -> Input {
        Input(
            caret: isCaretDodgeActive ? caretTracker.caretRect : nil,
            mouse: NSEvent.mouseLocation,
            primaryButtonDown: NSEvent.pressedMouseButtons & 1 != 0,
            modifiers: NSEvent.modifierFlags
        )
    }

    // MARK: Tick

    func tick(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let input = inputOverride ?? readInput()
        let settings = manager.settings

        let holdingPeekKeys = settings.peekThrough
            && input.modifiers.intersection([.control, .option, .command, .shift]) == Self.peekKeys
        if holdingPeekKeys {
            peekHeldSince = peekHeldSince ?? now
        } else {
            peekHeldSince = nil
        }
        let peeking = peekHeldSince.map { now - $0 >= Self.peekHoldDelay } ?? false
        let draggingThrough = settings.dragThrough && input.primaryButtonDown && dragStartedOutsideNotes
        if let lastMouse, lastMouse != input.mouse { lastPointerMove = now }
        lastMouse = input.mouse
        let pointerIsActive = now - lastPointerMove < Self.pointerActiveWindow
        let dodging = isCaretDodgeActive

        for controller in manager.visibleControllers {
            controller.syncHover(pointer: input.mouse)
            controller.setGhost(.peek, peeking)
            controller.setGhost(.drag, draggingThrough && controller.panel.frame.contains(input.mouse))
            if dodging {
                controller.updateDodge(caret: input.caret, pointer: input.mouse, pointerIsActive: pointerIsActive, now: now)
            }
        }
    }
}
