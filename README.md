# StickyTop

Sticky notes for macOS that **never leave the screen — and never get in the way**. Like Stickies, but every note floats above every app, on every desktop (Space), and over full-screen windows. It never takes focus away from the app you're using.

![StickyTop notes](docs/preview.png)

## Why it stays on top

macOS gives this behavior only to a specific combination of settings, and StickyTop uses all of them:

| Setting | What it does |
|---|---|
| Agent app (`LSUIElement`, `.accessory`) | No Dock icon. Its windows are also allowed into *other apps'* full-screen Spaces. |
| `NSPanel` + `.nonactivatingPanel` | Clicking or typing in a note doesn't activate StickyTop, so the full-screen app keeps its Space and menu bar. |
| Window level `.statusBar` | Sits above normal app windows and above other apps' floating palettes. |
| `.canJoinAllSpaces` | The note is on every desktop at once. |
| `.fullScreenAuxiliary` | The note can appear over full-screen apps. |
| `.stationary` | Mission Control and Show Desktop leave the note alone. |
| `hidesOnDeactivate = false` | Panels hide on app switch by default. This turns that off. |

`make verify` checks this end to end: a probe app goes full screen in its own Space, then asks the window server which windows are on screen, from front to back.

```
Full-screen probe window: (1512.0, 949.0) on a (1512.0, 982.0) screen, stack index 4
  StickyTop note on screen: stack index 1, layer 25, frame (1190.0, 64.0, 290.0, 300.0)
PASS: 1 note(s) visible in front of a full-screen app in another Space
```

![A note floating over a full-screen app](docs/fullscreen-proof.png)

## Never in the way

The usual complaint about always-on-top windows is that they cover the text you're typing. StickyTop notes move out of the way on their own:

- **Dodge text cursor.** When you type in another app and the text cursor gets close to a note, the note slides clear of that line (it prefers moving up or down, because typing moves the cursor sideways). After the cursor has been gone for a second, the note slides back. If a note is too big to move anywhere, it fades to a ghost instead. The spot you chose for the note is never overwritten.
- **See through while dragging.** Drag a file, a window or a text selection across a note and the note turns see-through, so the drop lands on whatever is underneath. A drag that starts inside a note, such as selecting its text, keeps the note solid.
- **Hold ⌃⌥ to peek.** While you hold Control-Option, every note turns see-through and clicks pass through to the app underneath. Quick ⌃⌥ shortcuts don't trigger it; the keys have to be held for 0.3 s.

Dodging the text cursor needs **Accessibility** access. Turn it on under the menu bar icon → **Never in the Way → Dodge Text Cursor — Allow Access…**. StickyTop reads only the cursor's position (the selected range and its bounds), never the text you type. It checks 10 times a second on a background queue with a 150 ms timeout, so a frozen app can't stall your notes. Idle CPU use is about 0.1%. Seeing through while dragging and peeking need no permission.

It works wherever apps report their text cursor to Accessibility, which covers most native Mac apps. Chromium and Electron apps (Chrome, Slack, VS Code…) are asked to switch their accessibility support on; how well they report the cursor varies. **After every update, grant access again.** This build is ad-hoc signed, so macOS ties the grant to the exact binary. After an update, System Settings still shows StickyTop switched **on**, but the grant no longer applies, and toggling it doesn't help. Remove StickyTop with **−** in **System Settings → Privacy & Security → Accessibility** and add it again with **+**. A Developer ID-signed build would keep the grant across updates.

## Features

- Unlimited notes in 6 Stickies colors, with rich text (bold, italic, underline, strikethrough, sizes, links).
- Drag the top bar to move a note. Drag any edge or corner to resize it.
- Double-click the top bar to collapse a note to one line. The line shows the note's title.
- Opacity levels of 100%, 85%, 70% and 50%. A translucent note turns solid while the pointer is over it.
- **Never in the way**: notes dodge your text cursor, let drags pass through, and turn see-through while you hold ⌃⌥ (see above).
- **Lock** (click-through): notes stay visible, but clicks pass through to the app underneath.
- **Global hotkeys** work from any app, with no Accessibility permission needed.
- **Recently Deleted**: the last 30 deleted notes can be restored from the menu bar. Blank notes are discarded.
- Paste cleanup: formatting survives a paste, but foreign colors and backgrounds are removed. White text copied from a dark-mode app won't disappear on paper.
- Auto-save, an atomic JSON store, a one-generation backup, and corrupt files are set aside, never deleted.
- Notes stranded on an unplugged monitor are pulled back on screen. **Gather Notes Here** collects them all.
- Launch at Login, so notes come back after a restart.
- Single instance: launching the app a second time just shows your notes.

## Shortcuts

| Anywhere | |
|---|---|
| ⌃⌥N | New note under the pointer |
| ⌃⌥H | Hide / show all notes |
| ⌃⌥L | Lock / unlock notes (click-through) |
| hold ⌃⌥ | Peek through every note |

| In a note | |
|---|---|
| ⌘N | New note (cascaded, same color) |
| ⌘W | Delete note (restore from menu bar) |
| ⌘M / double-click bar | Collapse / expand |
| ⌘1 … ⌘6 | Yellow, Blue, Green, Pink, Purple, Gray |
| ⌥⌘T | Cycle opacity |
| ⌘B ⌘I ⌘U ⇧⌘X | Bold, italic, underline, strikethrough |
| ⌘= / ⌘- | Bigger / smaller text |
| ⌥⇧⌘V | Paste as plain text |

Everything else is in the menu bar icon: the list of notes, Recently Deleted, Float Above Everything, Launch at Login, and Show Notes Folder.

## Install

Requires macOS 13 or later, and Xcode (or the Swift 6 toolchain) to build.

```bash
make install     # builds a universal StickyTop.app, copies it to /Applications, launches it
```

Other targets:

```bash
make test        # unit tests (model, persistence, geometry)
make app         # dist/StickyTop.app (ad-hoc signed)
make dmg         # dist/StickyTop-1.1.0.dmg (drag-to-Applications)
make verify      # full-screen overlay check (StickyTop must be running)
make verify-dodge  # real text-cursor dodge check (installed app needs Accessibility; hands off ~10 s)
```

In-app integration test (debug builds; uses a scratch folder, never your notes):

```bash
swift build && .build/debug/StickyTop --data-dir /tmp/stickytop-test --self-test
```

### Distributing to other Macs

The default build is ad-hoc signed, which is fine for your own Mac. For other Macs, sign with a Developer ID and notarize:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make dmg
xcrun notarytool submit dist/StickyTop-1.1.0.dmg --keychain-profile <profile> --wait
xcrun stapler staple dist/StickyTop-1.1.0.dmg
```

## Data

Notes live in `~/Library/Application Support/StickyTop/notes.json`. The previous session's copy is kept in `notes.backup.json`. Text is stored as a keyed-archived `NSAttributedString`, because RTF quietly turns the system font into Helvetica. Each note also has a `plainText` copy, so the file stays useful outside the app.

## Project layout

```
Sources/StickyCore/     Model, JSON store, frame + dodge geometry (pure Swift, unit-tested)
Sources/StickyTop/      AppKit app
  NotePanel.swift         The always-on-top window configuration
  NoteWindowController    One note: view setup, model sync, shortcuts, menu
  NoteManager             All notes: create/delete/restore, save, screens, prefs
  DodgeCoordinator        "Never in the way": caret dodge, drag-through, peek
  CaretTracker            Accessibility-based text-cursor finder (background queue)
  StatusMenuController    Menu bar icon + menu
  HotKeys.swift           Carbon global hotkeys
  SelfTest.swift          In-process integration test (DEBUG only)
Tests/StickyCoreTests/  Swift Testing suites
scripts/                App bundling, icon renderer, DMG, full-screen probe
```

## Known limits

- Nothing can draw over the login window, the lock screen, or secure system prompts. Apps that take exclusive control of the display (some games, some slideshow modes) are the same.
- Launch at Login may ask for approval in **System Settings → General → Login Items** the first time.
