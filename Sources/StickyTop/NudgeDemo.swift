#if DEBUG
import AppKit
import StickyCore

/// Live, narrated demo of Keep Fresh nudges (debug builds only):
///
///     swift build && .build/debug/StickyTop --demo-nudges
///
/// Uses a throwaway notes folder, plays for about 35 seconds, then quits.
@MainActor
enum NudgeDemo {
    static func run(manager: NoteManager) async {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let midX = screen.midX, midY = screen.midY

        let narrator = manager.addDemoNote(
            "Keep Fresh — live demo\n\nWatch the notes on the right.",
            color: .gray, frame: CGRect(x: midX - 420, y: midY - 20, width: 300, height: 170))
        let dentist = manager.addDemoNote(
            "Call dentist to reschedule Friday 3pm",
            color: .yellow, frame: CGRect(x: midX - 90, y: midY - 10, width: 280, height: 190),
            createdDaysAgo: 3)
        let release = manager.addDemoNote(
            "Ship v1.2 release notes",
            color: .blue, frame: CGRect(x: midX + 210, y: midY - 10, width: 260, height: 190),
            createdDaysAgo: 1)
        let plants = manager.addDemoNote(
            "Water the plants",
            color: .green, frame: CGRect(x: midX - 90, y: midY - 230, width: 280, height: 150),
            collapsed: true, createdDaysAgo: 2)
        for controller in [narrator, dentist, release, plants] { controller.setKeepFresh(true) }
        narrator.setKeepFresh(false)

        // Start the on-device rewording early; the model takes a few seconds.
        let rewording: Task<String?, Never> = Task {
            await Rephraser.reword("Call dentist to reschedule Friday 3pm", variation: 2)
        }

        func narrate(_ text: String) {
            narrator.textView.string = text
            narrator.textView.textStorage?.setAttributes(Theme.typingAttributes,
                range: NSRange(location: 0, length: narrator.textView.string.utf16.count))
        }
        func pause(_ seconds: Double) async {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }

        await pause(2.5)
        narrate("1 · A nudge\n\nSoft double flash, a new shade of the note's color, and a reminder card with how long it's been pinned.")
        dentist.nudge(rewording: nil)
        await pause(7)

        narrate("2 · It never reads the same way twice\n\nWording rotates with every nudge, so it doesn't become wallpaper.")
        release.nudge(rewording: nil)
        await pause(7)

        narrate("3 · Collapsed notes\n\nNo room for a card, so the drag bar carries the reminder.")
        plants.nudge(rewording: nil)
        await pause(7)

        let reworded = await rewording.value
        if let reworded {
            narrate("4 · ✦ Apple Intelligence (optional)\n\nReworded on-device, marked ✦. Your note's own text stays unchanged above.")
            dentist.nudge(rewording: reworded)
        } else {
            narrate("4 · ✦ Apple Intelligence (optional)\n\nNo safe rewording this time, so it uses your own words — it never shows anything unchecked.")
            dentist.nudge(rewording: nil)
        }
        await pause(8)

        narrate("That's Keep Fresh.\n\nTurn it on from any note's ••• menu. Demo ending…")
        await pause(3.5)
        NSApp.terminate(nil)
    }
}

extension NoteManager {
    /// A note placed exactly where the demo wants it.
    func addDemoNote(_ text: String, color: NoteColor, frame: CGRect,
                     collapsed: Bool = false, createdDaysAgo: Double = 0) -> NoteWindowController {
        let note = Note(plainText: text, frame: frame, color: color, isCollapsed: collapsed,
                        createdAt: Date().addingTimeInterval(-createdDaysAgo * 86_400))
        return openForDemo(note)
    }
}
#endif
