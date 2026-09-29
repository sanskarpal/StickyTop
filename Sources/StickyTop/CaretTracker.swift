import AppKit
import ApplicationServices
import StickyCore

/// Finds the text cursor (caret) of whatever app you're typing in, using the
/// Accessibility API. Needs the user to grant StickyTop Accessibility access.
///
/// Polls ~10×/s on a background queue with a short AX timeout, so a hung app
/// can never stall the notes. Publishes the caret in AppKit screen coordinates.
final class CaretTracker {
    /// Latest caret rect (AppKit global coordinates), or nil when there's no
    /// text caret outside StickyTop. Main thread only.
    private(set) var caretRect: CGRect?

    private let queue = DispatchQueue(label: "com.sanskarpal.StickyTop.caret", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private let systemWide = AXUIElementCreateSystemWide()
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    /// Apps already asked to expose their accessibility tree (queue only).
    private var primedPIDs = Set<pid_t>()

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "allow Accessibility" prompt (once per app install).
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        AXUIElementSetMessagingTimeout(systemWide, 0.15)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(30))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let topLeftRect = self.readCaret()
            DispatchQueue.main.async {
                self.publish(topLeftRect)
            }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        caretRect = nil
    }

    private func publish(_ topLeftRect: CGRect?) {
        guard timer != nil else { return }
        guard let topLeftRect, let primary = NSScreen.screens.first else {
            caretRect = nil
            return
        }
        caretRect = ScreenSpace.appKitRect(fromTopLeft: topLeftRect, primaryScreenHeight: primary.frame.height)
    }

    // MARK: Accessibility (background queue)

    /// The caret of the focused text element, in top-left-origin coordinates.
    private func readCaret() -> CGRect? {
        guard AXIsProcessTrusted(),
              let element = copyElement(systemWide, kAXFocusedUIElementAttribute) else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != ownPID else { return nil } // typing in a note: nothing to dodge
        prime(pid)

        guard let rangeValue = copyValue(element, kAXSelectedTextRangeAttribute) else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &selection), selection.location != kCFNotFound else { return nil }

        // A short single-line selection counts as "where you're working".
        if selection.length > 0, let rect = bounds(of: selection, in: element), NoteDodge.isPlausibleCaret(rect) {
            return rect
        }
        // Zero-length range = the caret itself. Many apps return nothing for
        // that, so fall back to the character after, then before, the caret.
        if let rect = bounds(of: CFRange(location: selection.location, length: 0), in: element),
           NoteDodge.isPlausibleCaret(rect) {
            return rect
        }
        if let next = bounds(of: CFRange(location: selection.location, length: 1), in: element),
           NoteDodge.isPlausibleCaret(next) {
            return CGRect(x: next.minX, y: next.minY, width: 1, height: next.height)
        }
        if selection.location > 0,
           let previous = bounds(of: CFRange(location: selection.location - 1, length: 1), in: element),
           NoteDodge.isPlausibleCaret(previous) {
            return CGRect(x: previous.maxX, y: previous.minY, width: 1, height: previous.height)
        }
        return nil
    }

    /// Chromium and Electron apps (Chrome, Slack, VS Code…) only build their
    /// accessibility tree when asked. Harmless for every other app.
    private func prime(_ pid: pid_t) {
        guard !primedPIDs.contains(pid) else { return }
        primedPIDs.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private func bounds(of range: CFRange, in element: AXUIElement) -> CGRect? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &result
        ) == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(result as! AXValue, .cgRect, &rect) ? rect : nil
    }

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func copyValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
