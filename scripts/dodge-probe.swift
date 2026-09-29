// End-to-end check of "Dodge Text Cursor" with the real Accessibility API.
//
// Requires: /Applications/StickyTop.app installed and granted Accessibility access.
// Launches a separate StickyTop instance on a scratch notes folder (your notes
// are untouched), opens a text window underneath its note, moves the caret
// under the note and asks the window server whether the note got out of the way
// — and whether it came back afterwards.
//
// Usage: make verify-dodge   (bundles the probe as an .app and launches it with
// `open`, because macOS only lets a LaunchServices-launched app take focus)
import AppKit

final class Probe: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var textView: NSTextView!
    private var sticky: NSRunningApplication?
    private var home = CGRect.zero
    private var failures = 0
    /// PROBE_CONTROL=1: same run with dodging off, to see if anything *else* moves notes.
    private let isControl = ProcessInfo.processInfo.environment["PROBE_CONTROL"] != nil
    private let dataDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("stickytop-dodge-probe-\(UUID().uuidString)")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let visible = NSScreen.main!.visibleFrame
        let windowFrame = CGRect(x: visible.minX + 80, y: visible.minY + 80, width: 820, height: 520)
        home = CGRect(x: windowFrame.minX + 300, y: windowFrame.minY + 110, width: 260, height: 200)

        // A window full of text, like a document you're writing.
        window = NSWindow(contentRect: windowFrame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "StickyTop Dodge Probe"
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = window.contentView!.bounds
        textView = (scroll.documentView as! NSTextView)
        textView.font = .systemFont(ofSize: 15)
        textView.string = (1...40).map { "Line \($0): the quick brown fox jumps over the lazy dog, again and again." }
            .joined(separator: "\n")
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)
        textView.setSelectedRange(NSRange(location: 0, length: 0)) // top line, far from the note

        waitUntilFrontmost(attempts: 30)
    }

    /// The probe's caret only counts once macOS has actually made it frontmost.
    private func waitUntilFrontmost(attempts: Int) {
        if NSApp.isActive && window.isKeyWindow {
            launchStickyTop()
        } else if attempts == 0 {
            print("FAIL: macOS didn't bring the probe to the front (launch it with `open`, not from a shell)")
            exit(2)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.waitUntilFrontmost(attempts: attempts - 1) }
        }
    }

    private func launchStickyTop() {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let note: [String: Any] = [
            "plainText": "Dodge probe note",
            "color": "blue",
            "frame": [[home.minX, home.minY], [home.width, home.height]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: ["version": 1, "notes": [note], "trash": []])
        try! data.write(to: dataDir.appendingPathComponent("notes.json"))

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = false
        config.arguments = ["--data-dir", dataDir.path] + (isControl ? ["-dodgeCaret", "NO"] : [])
        let appPath = ProcessInfo.processInfo.environment["PROBE_APP"] ?? "/Applications/StickyTop.app"
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: config) { app, error in
            DispatchQueue.main.async {
                guard let app else {
                    print("FAIL: could not launch StickyTop: \(error?.localizedDescription ?? "?")")
                    exit(2)
                }
                self.sticky = app
                if ProcessInfo.processInfo.environment["PROBE_TRACE"] != nil { self.startTrace() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.run() }
            }
        }
    }

    private func check(_ ok: Bool, _ label: String) {
        print(ok ? "  ✔ \(label)" : "  ✘ \(label)")
        if !ok { failures += 1 }
    }

    /// The scratch note's frame from the window server, in AppKit coordinates.
    private func noteFrame() -> CGRect? {
        guard let pid = sticky?.processIdentifier else { return nil }
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let primaryHeight = NSScreen.screens[0].frame.height
        for info in windows where (info[kCGWindowOwnerPID as String] as? Int32) == pid {
            guard let b = CGRect(dictionaryRepresentation: info[kCGWindowBounds as String] as! CFDictionary),
                  b.width >= 200 else { continue }
            return CGRect(x: b.minX, y: primaryHeight - b.maxY, width: b.width, height: b.height)
        }
        return nil
    }

    private var traceStart = Date()
    private func startTrace() {
        traceStart = Date()
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let t = Date().timeIntervalSince(self.traceStart)
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            let notes = self.allStickyWindows().map(self.fmt).joined(separator: " | ")
            print(String(format: "    [%.1fs] front=%@ probeKey=%@ note=%@", t, front, self.window.isKeyWindow ? "yes" : "NO", notes))
        }
    }

    private func allStickyWindows() -> [CGRect] {
        guard let pid = sticky?.processIdentifier else { return [] }
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let primaryHeight = NSScreen.screens[0].frame.height
        return windows.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let b = CGRect(dictionaryRepresentation: info[kCGWindowBounds as String] as! CFDictionary) else { return nil }
            return CGRect(x: b.minX, y: primaryHeight - b.maxY, width: b.width, height: b.height)
        }
    }

    /// Puts the caret at a screen point inside the text view; returns the caret rect.
    private func placeCaret(at screenPoint: CGPoint) -> CGRect {
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = textView.convert(windowPoint, from: nil)
        let index = textView.characterIndexForInsertion(at: viewPoint)
        textView.setSelectedRange(NSRange(location: index, length: 0))
        return textView.firstRect(forCharacterRange: NSRange(location: index, length: 0), actualRange: nil)
    }

    private func run(attempts: Int = 30) {
        // Launching StickyTop can steal focus; the probe's caret only counts while it's frontmost.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier || !window.isKeyWindow {
            guard attempts > 0 else {
                print("INCONCLUSIVE: another app kept focus (please leave the Mac alone for ~10 s and rerun)")
                finish(inconclusive: true)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.run(attempts: attempts - 1) }
            return
        }
        print("StickyTop dodge probe (real Accessibility)\(isControl ? " — CONTROL: dodging off" : "")")
        let start = noteFrame()
        check(start.map { abs($0.minX - home.minX) < 1 && abs($0.minY - home.minY) < 1 } == true,
              "scratch note is at home \(fmt(home)) — got \(start.map(fmt) ?? "none")")

        // Type "behind" the note: caret on a line inside it.
        let caret = placeCaret(at: CGPoint(x: home.midX, y: home.minY + 40))
        print("    caret now at \(fmt(caret))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let stillFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            let dodged = self.noteFrame()
            let zone = caret.insetBy(dx: -90, dy: -14)
            let onScreen = NSScreen.main!.visibleFrame
            if self.isControl {
                self.check(dodged.map { abs($0.minX - self.home.minX) < 1 && abs($0.minY - self.home.minY) < 1 } == true,
                           "with dodging off, nothing moves the note — now \(dodged.map(self.fmt) ?? "none")")
            } else {
                self.check(stillFront, "probe stayed frontmost during the dodge")
                self.check(dodged.map { !$0.intersects(zone) && onScreen.contains($0) } == true,
                           "note slid clear of the text cursor and stayed on screen — now \(dodged.map(self.fmt) ?? "none")")
            }

            // Move the caret back to the top line; the note should come home.
            self.textView.setSelectedRange(NSRange(location: 0, length: 0))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                let back = self.noteFrame()
                self.check(back.map { abs($0.minX - self.home.minX) < 1 && abs($0.minY - self.home.minY) < 1 } == true,
                           "note returned home after the cursor left — now \(back.map(self.fmt) ?? "none")")
                self.finish()
            }
        }
    }

    private func finish(inconclusive: Bool = false) {
        sticky?.terminate()
        try? FileManager.default.removeItem(at: dataDir)
        if inconclusive { exit(3) }
        let passText = isControl ? "PASS (control): nothing but StickyTop's dodge moves notes" : "PASS: note dodged the real text cursor and came back"
        print(failures == 0 ? passText : "FAIL: \(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private func fmt(_ r: CGRect) -> String {
        "(\(Int(r.minX)), \(Int(r.minY)), \(Int(r.width))×\(Int(r.height)))"
    }
}

let app = NSApplication.shared
let probe = Probe()
app.delegate = probe
app.setActivationPolicy(.regular)
app.run()
