// End-to-end check of StickyTop's core promise: notes stay visible over a
// full-screen app in its own Space.
//
// Opens a window, takes it full screen (macOS moves it to a new Space), then
// asks the window server which windows are on screen, front to back. Passes if
// StickyTop's note windows are on screen and in front of the full-screen window.
//
// Usage: swiftc -O scripts/overlay-probe.swift -o build/overlay-probe && build/overlay-probe [screenshot.png]
import AppKit

final class Probe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let screenshotPath = CommandLine.arguments.dropFirst().first
    private var exitCode: Int32 = 1

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 640, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "StickyTop Overlay Probe"
        window.backgroundColor = NSColor(srgbRed: 0.10, green: 0.45, blue: 0.55, alpha: 1)
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.window.toggleFullScreen(nil) }
        // Bail out if full screen never happens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            print("FAIL: window never entered full screen")
            exit(2)
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.inspect() }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        exit(exitCode)
    }

    private func inspect() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        let myPID = ProcessInfo.processInfo.processIdentifier

        func bounds(_ info: [String: Any]) -> CGRect {
            CGRect(dictionaryRepresentation: info[kCGWindowBounds as String] as! CFDictionary) ?? .zero
        }
        let probeIndex = windows.firstIndex {
            ($0[kCGWindowOwnerPID as String] as? Int32) == myPID && bounds($0).height > 300
        }
        // Note panels (the menu bar icon is also a StickyTop window, but only ~24pt tall).
        let notes = windows.enumerated().filter { _, info in
            (info[kCGWindowOwnerName as String] as? String) == "StickyTop" && bounds(info).height >= 26 && bounds(info).width >= 100
        }

        let screen = NSScreen.main!.frame
        print("Full-screen probe window: \(bounds(windows[probeIndex ?? 0]).size) on a \(screen.size) screen, stack index \(probeIndex ?? -1)")
        for (index, info) in notes {
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            print("  StickyTop note on screen: stack index \(index), layer \(layer), frame \(bounds(info))")
        }

        if let path = screenshotPath {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", path]
            try? task.run()
            task.waitUntilExit()
            print("Screenshot: \(path)")
        }

        if let probeIndex, !notes.isEmpty, notes.allSatisfy({ $0.offset < probeIndex }) {
            print("PASS: \(notes.count) note(s) visible in front of a full-screen app in another Space")
            exitCode = 0
        } else if notes.isEmpty {
            print("FAIL: no StickyTop notes on screen over the full-screen window (is StickyTop running with notes visible?)")
        } else {
            print("FAIL: notes are on screen but behind the full-screen window")
        }
        window.toggleFullScreen(nil)
    }
}

let app = NSApplication.shared
let probe = Probe()
app.delegate = probe
app.setActivationPolicy(.regular)
app.run()
