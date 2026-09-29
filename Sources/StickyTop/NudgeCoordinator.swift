import AppKit
import StickyCore

/// Runs "Keep Fresh" nudges: checks fresh notes on a slow timer and nudges the
/// ones that are due — one at a time, never while you're typing in them, while
/// they're dodging, while notes are hidden, or while nudges are paused.
@MainActor
final class NudgeCoordinator {
    static let checkInterval: TimeInterval = 20

    /// Tests drive `tick(now:)` themselves.
    var automaticTicks = true {
        didSet { refresh() }
    }
    /// Tests turn this off so wording is deterministic.
    var allowsRewording = true

    private(set) var pausedUntil: Date?
    private unowned let manager: NoteManager
    private var timer: Timer?
    /// Rewordings made ahead of time (the on-device model takes seconds), keyed by
    /// note, with the line they reword so an edited note never shows a stale one.
    private var prepared: [UUID: (source: String, text: String)] = [:]
    private var preparing = Set<UUID>()

    /// Rewording is opt-in and needs Apple Intelligence.
    var isRewordingEnabled: Bool {
        allowsRewording && manager.settings.rewordWithAI && Rephraser.isAvailable
    }

    func hasPreparedRewording(for controller: NoteWindowController) -> Bool {
        prepared[controller.id]?.source == Self.reminderLine(of: controller.note)
    }

    init(manager: NoteManager) {
        self.manager = manager
    }

    func isPaused(at now: Date = Date()) -> Bool {
        pausedUntil.map { $0 > now } ?? false
    }

    func pause(for duration: TimeInterval, now: Date = Date()) {
        pausedUntil = now + duration
        manager.visibleControllers.forEach { $0.dismissNudge() }
    }

    func resume() {
        pausedUntil = nil
    }

    /// Runs the timer only while some visible note is kept fresh.
    func refresh() {
        let wanted = automaticTicks && manager.visibleControllers.contains { $0.note.keepFresh }
        if wanted, timer == nil {
            let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !wanted, let timer {
            timer.invalidate()
            self.timer = nil
        }
    }

    func tick(now: Date = Date()) {
        if isPaused(at: now) { return }
        pausedUntil = nil
        guard !manager.isHidden else { return }
        prepareRewordings()
        // One note per check, most overdue first, so several fresh notes don't flash at once.
        let due = manager.visibleControllers.filter { $0.note.isDueForNudge(at: now) && $0.canNudge }
        guard let next = due.min(by: { dueDate($0) < dueDate($1) }) else { return }
        nudge(next, now: now)
    }

    /// "Nudge Fresh Notes Now": every visible fresh note, a moment apart.
    func nudgeNow() {
        let fresh = manager.visibleControllers.filter { $0.note.keepFresh && $0.canNudge }
        for (index, controller) in fresh.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 1.2) { [weak self, weak controller] in
                MainActor.assumeIsolated {
                    guard let self, let controller, controller.canNudge else { return }
                    self.nudge(controller, now: Date())
                }
            }
        }
    }

    private func dueDate(_ controller: NoteWindowController) -> Date {
        let note = controller.note
        return FreshSchedule.nextNudge(after: note.lastNudge ?? note.freshAnchor ?? note.createdAt,
                                       anchor: note.freshAnchor ?? note.createdAt)
    }

    private func nudge(_ controller: NoteWindowController, now: Date) {
        let line = Self.reminderLine(of: controller.note)
        let rewording = isRewordingEnabled ? prepared.removeValue(forKey: controller.id).flatMap {
            $0.source == line ? $0.text : nil
        } : nil
        controller.nudge(rewording: rewording, now: now)
        prepareRewording(for: controller) // the next nudge's wording
    }

    /// Makes sure every visible fresh note has a rewording ready (no-op when off).
    func prepareRewordings() {
        manager.visibleControllers.filter { $0.note.keepFresh }.forEach(prepareRewording(for:))
    }

    private func prepareRewording(for controller: NoteWindowController) {
        let id = controller.id
        let line = Self.reminderLine(of: controller.note)
        guard isRewordingEnabled, controller.note.keepFresh, !line.isEmpty, !preparing.contains(id),
              prepared[id]?.source != line else { return }
        preparing.insert(id)
        let variation = controller.note.nudgeCount
        Task { @MainActor [weak self] in
            let text = await Rephraser.reword(line, variation: variation)
            guard let self else { return }
            self.preparing.remove(id)
            if let text { self.prepared[id] = (line, text) }
        }
    }

    /// The line a nudge reminds you of: the note's first line, untruncated.
    static func reminderLine(of note: Note) -> String {
        note.isBlank ? "" : Note.title(for: note.plainText, maxLength: 200)
    }
}
