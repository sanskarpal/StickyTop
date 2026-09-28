import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts via Carbon's `RegisterEventHotKey`, which (unlike
/// event taps) needs no Accessibility permission.
@MainActor
final class HotKeyCenter {
    struct Shortcut {
        let keyCode: Int
        let modifiers: Int

        /// ⌃⌥ + key — the family StickyTop uses.
        static func controlOption(_ keyCode: Int) -> Shortcut {
            Shortcut(keyCode: keyCode, modifiers: controlKey | optionKey)
        }
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private static let signature: OSType = 0x5354_4B59 // 'STKY'

    @discardableResult
    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            UInt32(shortcut.modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            NSLog("StickyTop: could not register hotkey \(shortcut.keyCode) (status \(status))")
            return false
        }
        hotKeyRefs.append(ref)
        handlers[id] = handler
        return true
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            // Carbon delivers hotkey events on the main thread.
            MainActor.assumeIsolated { center.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &eventType, context, &eventHandler)
    }
}
