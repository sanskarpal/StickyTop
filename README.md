# StickyTop

Sticky notes for macOS that **never leave the screen**. Like Stickies, but every note floats above every app, on every desktop (Space), and over full-screen windows. It never takes focus away from the app you're using.

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

## Features

- Unlimited notes in 6 Stickies colors, with rich text (bold, italic, underline, strikethrough, sizes, links).
- Drag the top bar to move a note. Drag any edge or corner to resize it.
- Double-click the top bar to collapse a note to one line. The line shows the note's title.
- Opacity levels of 100%, 85%, 70% and 50%. A translucent note turns solid while the pointer is over it.
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
make dmg         # dist/StickyTop-1.0.0.dmg (drag-to-Applications)
make verify      # full-screen overlay check (StickyTop must be running)
```

In-app integration test (debug builds; uses a scratch folder, never your notes):

```bash
swift build && .build/debug/StickyTop --data-dir /tmp/stickytop-test --self-test
```

### Distributing to other Macs

The default build is ad-hoc signed, which is fine for your own Mac. For other Macs, sign with a Developer ID and notarize:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make dmg
xcrun notarytool submit dist/StickyTop-1.0.0.dmg --keychain-profile <profile> --wait
xcrun stapler staple dist/StickyTop-1.0.0.dmg
```

## Data

Notes live in `~/Library/Application Support/StickyTop/notes.json`. The previous session's copy is kept in `notes.backup.json`. Text is stored as a keyed-archived `NSAttributedString`, because RTF quietly turns the system font into Helvetica. Each note also has a `plainText` copy, so the file stays useful outside the app.

## Project layout

```
Sources/StickyCore/     Model, JSON store, frame geometry (pure Swift, unit-tested)
Sources/StickyTop/      AppKit app
  NotePanel.swift         The always-on-top window configuration
  NoteWindowController    One note: view setup, model sync, shortcuts, menu
  NoteManager             All notes: create/delete/restore, save, screens, prefs
  StatusMenuController    Menu bar icon + menu
  HotKeys.swift           Carbon global hotkeys
  SelfTest.swift          In-process integration test (DEBUG only)
Tests/StickyCoreTests/  Swift Testing suites
scripts/                App bundling, icon renderer, DMG, full-screen probe
```

## Known limits

- Nothing can draw over the login window, the lock screen, or secure system prompts. Apps that take exclusive control of the display (some games, some slideshow modes) are the same.
- Launch at Login may ask for approval in **System Settings → General → Login Items** the first time.
