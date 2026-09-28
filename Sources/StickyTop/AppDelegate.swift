import AppKit
import Carbon.HIToolbox
import StickyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Posted by a second copy of the app so the running one shows its notes.
    static let showNotesNotification = Notification.Name("com.sanskarpal.StickyTop.showNotes")

    private var manager: NoteManager!
    private var statusMenu: StatusMenuController!
    private let hotKeys = HotKeyCenter()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon, and — crucially — its panels may join other
        // apps' full-screen Spaces. (Info.plist also sets LSUIElement.)
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = LaunchOptions()
        // A scratch --data-dir instance is for development and may run alongside the real one.
        let isScratchInstance = options.dataDirectory != nil
        if !isScratchInstance, handOffToRunningInstance() {
            NSApp.terminate(nil)
            return
        }

        // Stay alive and flush saves even when macOS would like to reap an idle agent.
        ProcessInfo.processInfo.disableAutomaticTermination("Sticky notes stay on screen")
        ProcessInfo.processInfo.disableSuddenTermination()

        manager = NoteManager(store: options.dataDirectory.map { NoteStore(directory: $0) } ?? NoteStore())
        manager.start()

        #if DEBUG
        if options.selfTest {
            guard isScratchInstance else {
                print("--self-test needs --data-dir so it never touches your real notes")
                exit(2)
            }
            Task { @MainActor [manager] in await SelfTest.run(manager: manager!) }
            return
        }
        #endif

        if let snapshotDirectory = options.snapshotDirectory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [manager] in
                manager?.writeSnapshots(to: snapshotDirectory)
                NSApp.terminate(nil)
            }
            return
        }

        statusMenu = StatusMenuController(manager: manager)
        manager.onStateChange = { [weak self] in self?.statusMenu.updateIcon() }
        if !isScratchInstance { registerHotKeys() }
        observeSystem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager?.saveNow()
    }

    /// Launching the app again (Finder, Spotlight, Dock) brings hidden notes back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        manager?.showAll()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: Setup

    private func registerHotKeys() {
        hotKeys.register(.controlOption(kVK_ANSI_N)) { [weak self] in self?.manager.createNote() }
        hotKeys.register(.controlOption(kVK_ANSI_H)) { [weak self] in self?.manager.toggleVisibility() }
        hotKeys.register(.controlOption(kVK_ANSI_L)) { [weak self] in self?.manager.toggleClickThrough() }
    }

    private func observeSystem() {
        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observe(app, NSApplication.didChangeScreenParametersNotification) { manager in
            manager.keepNotesOnScreen()
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { manager in
            manager.reassertStacking()
        }
        observe(workspace, NSWorkspace.didWakeNotification) { manager in
            manager.keepNotesOnScreen()
            manager.reassertStacking()
        }
        observe(distributed, Self.showNotesNotification) { manager in
            manager.showAll()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping (NoteManager) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let manager = self?.manager else { return }
                action(manager)
            }
        }
        observers.append((center, token))
    }

    /// Returns true if another copy is already running (and was told to show its notes).
    private func handOffToRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            Self.showNotesNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
        return true
    }
}
