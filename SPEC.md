# Jott — Product Specification

## Overview

Jott is a macOS menu-bar note-taking app built around a notch-anchored overlay panel. It lives at the top of every screen behind the macOS notch, giving instant capture and recall without switching apps. Notes, reminders, and calendar events are created via natural language; the overlay morphs between a compact notch pill and a full capture surface using spring physics.

---

## Platform

- macOS 12+ (Monterey or later required for notch APIs)
- SwiftUI + AppKit hybrid (NSPanel for window management, SwiftUI for all UI)
- No main window — lives entirely as a MenuBarExtra + floating NSPanel

---

## Entry Points

| Trigger | Effect |
|---|---|
| Double-tap Option key | Toggle overlay open/close |
| Menu bar icon | Opens MenuBarExtra dropdown |
| "Open Jott" button in dropdown | Calls `toggleOverlay()` |
| Remote note tap from menu | Opens that note in detail view |

The double-tap is detected via a `CGEvent.tapCreate` session-level event tap watching `flagsChanged`. Two consecutive Option-only taps within 0.65 s fire the action. Re-entrant taps while Option is held (held key repeat) are suppressed.

---

## Window Architecture

### OverlayPanel (NSPanel)

- Fixed 460 × 640 pt, positioned so its top edge is flush with the top of the screen at the notch center (`screen.midX − 230, screen.maxY − 640`).
- Transparent, borderless, above menu bar level (`CGWindowLevelForKey(.statusWindow) + 1`).
- `canJoinAllSpaces`, `fullScreenAuxiliary` — visible on all Spaces and over full-screen apps.
- `hidesOnDeactivate = false` — stays visible when another app is focused (unless isLocked = false and click outside).
- Shadow is rendered by SwiftUI, not the window, so it follows the clip shape.

The panel's content view is `FirstMouseHostingView<OverlayView>`, a subclass that:
- overrides `acceptsFirstMouse` → true (single-click works without pre-focusing)
- returns `intrinsicContentSize = .zero` (prevents SwiftUI from calling `updateAnimatedWindowSize`, which would trigger a layout loop)
- no-ops `windowDidLayout` (same reason)

**Frame management is entirely explicit.** SwiftUI is never allowed to resize the panel.

### FocusNotePanel (NSPanel)

A separate panel that renders the "pinned note pill" at the notch when the overlay is closed but a note is pinned (`viewModel.focusedNote != nil`). Same level as the overlay panel, also `canJoinAllSpaces`. Its frame animates via `NSAnimationContext` (Core Animation), not SwiftUI layout.

---

## Overlay Open/Close Animation

### Open sequence

All driven from `OverlayWindowController.show()`:

1. **t = 0 ms** — Set `morphWidth`, `morphHeight`, `morphRadius` to compact start values.
   - If no focused note: 178 × 32 pt, radius 11
   - If focused note: starts at the pill's current pixel footprint (compact or expanded)
2. **t = 0 ms** — `withAnimation(openSpring)` → animate `morphWidth` to 460 pt.
   - `openSpring` = `interpolatingSpring(mass:1.0, stiffness:130, damping:21, initialVelocity:1.0)`
3. **t = 60 ms** — Second `withAnimation(openSpring)` → animate `morphHeight` to `overlayExpandedHeight + 116` and `morphRadius` to 8.
   - The 60 ms stagger gives a "width-first inhale" effect.
4. **t = 170 ms** — `contentVisible = true` — content fades in over 0.18 s (`easeOut`).
5. Text view is focused at t=0 and again at t=50 ms (double-tap ensures focus survives AppKit focus-change events).

### Close sequence

Driven from `OverlayWindowController.dismiss()`:

1. `contentVisible = false` — content hides instantly (no animation).
2. `withAnimation(closeEasing)` → animate `morphWidth`, `morphHeight`, `morphRadius` back to compact values.
   - `closeEasing` = `timingCurve(0.22, 0, 0, 1, duration: 0.42)` — decisive cubic-bezier, no bounce.
3. **t = 440 ms** — Reset morph values to defaults, set `panel.alphaValue = 0`, call `panel.orderOut`.

**Rule:** Width springs open with mass/stiffness; close uses a tight cubic-bezier. Exit animation is never interrupted by content UI.

### Height during open session

While the overlay is open, `overlayExpandedHeight` is recomputed every time `viewModel` changes:

- Empty input: 132 pt
- Short text (≤260 chars, no newlines): 250 pt
- Long text or multiline: 380 pt
- Command mode or slash prefix: 540 pt

Any change > 1 pt triggers `withAnimation(.interpolatingSpring(mass:0.9, stiffness:200, damping:26))` on `morphHeight`. The 116 pt floating allowance is always added (keeps Aa/mic buttons outside the clip shape).

---

## Clip Shape: JottNotchShape

A custom `Shape` with three independently animatable properties: `width`, `height`, `radius`. All three participate in `animatableData` so SwiftUI can interpolate them simultaneously.

Geometry: flat top (bleeds 2 pt above the rect to seal the physical notch seam), rounded bottom corners only. The shape is centered horizontally in the 460 pt panel so it always aligns with the notch regardless of exact notch width.

The OverlayView wraps UnifiedJottView in `.clipShape(JottNotchShape(...))`, so the black void surface, content, and shadow all clip together.

---

## Focus Note Pill

When `viewModel.focusedNote != nil` and the overlay is closed, a persistent pill lives at the notch rendered by `FocusNotePillController`.

### Pill states

| State | Frame | Height | Shape |
|---|---|---|---|
| Compact | notchW + 2×62 pt wide | 34 pt | LiquidNotchSurface, radius 11 |
| Hover | same wide | 70 pt | radius 15, bottomBulge 2.4 |
| Expanded | 370 pt wide | 462 pt | radius 18, no bulge |

`LiquidNotchSurface` is a `Shape` with animatable `bottomRadius` + `bottomBulge`. The bulge is a Bezier control-point offset at the bottom center, creating a subtle downward belly when hovered.

### Pill animations

| Transition | Duration | Timing |
|---|---|---|
| Compact → hover | 0.22 s | CAMediaTimingFunction(0.18, 0.86, 0.25, 1.0) |
| Hover → compact | 0.18 s | same |
| Compact/hover → expanded | 0.46 s | interpolatingSpring(mass:0.92, stiffness:170, damping:27) |
| Expanded → compact | 0.34 s | same spring |
| Control icons reveal on pin | 0.08 s delay, then spring(mass:0.78, stiffness:230, damping:21) | slide in from sides |
| Hover text fade-in | 0.07 s delay, easeOut 0.14 s | — |
| Hover text fade-out | easeOut 0.07 s | — |

All frame animations use `NSAnimationContext.runAnimationGroup` (Core Animation), not SwiftUI, to avoid tracking-area oscillation from SwiftUI proxy.size updates during animation.

Mouse events are suppressed during frame animation (`panel.ignoresMouseEvents = true`) and restored in the completion handler to prevent spurious `onHover` entry/exit.

### Pill ↔ overlay handoff

- **Overlay open:** `FocusNotePillController.hideForHandoff()` is called synchronously inside `OverlayWindowController.show()` before the panel is ordered front. For a compact pill, the pill stays visible behind the bar (same pixel footprint, no seam). For an expanded pill, it hides instantly and `isExpanded` resets.
- **Overlay close:** After 0.36 s (the close spring settles by ~0.28 s), `showPill(fromBar: true)` is called. If the pill was compact and stayed visible, it just moves to front. If it was hidden (expanded handoff), it fades in over 0.14 s.

---

## Capture Surface (JottCaptureView)

The main input surface rendered when no note is selected.

### Layout (top to bottom)

1. **Toolbar row** — `?` help button (left), status/feedback chip (center, conditional), clipboard offer chip (conditional), lock button (right).
2. **JottInputArea** — The `JottNSTextView` wrapper. Expands as text grows. Supports paste of images from clipboard.
3. **Dropdown section** — Floats below input; only renders when `showsDropdown && dropdownReady`. `dropdownReady` is set 180 ms after open to avoid flash.
4. **Floating actions** — `Aa` format bar toggle + mic button. These live outside the notch clip so they appear below it.

The entire notch panel (toolbar + input) has background `jottNotchVoidBlack` = `NSColor(calibratedWhite: 0.015, alpha: 1.0)`. Near-black instead of pure black to avoid harsh edge contrast against bright wallpapers.

### Input state machine

```
Empty input
  → type text → Short draft (autosave at 0.8 s debounce)
  → type "/" → Slash picker dropdown
  → type "?" → Help card dropdown
  → type "/note " → Forced note mode (prefix stripped, type locked)
  → type "/reminder " → Forced reminder mode

Short draft (note mode)
  → Cmd+Return → commitSession() → feedback chip, clear
  → Esc → dismiss() (saves if non-empty)
  → close (click outside / ⌥⌥) → commitSession(), then dismiss

Forced note/reminder mode
  → type text, Enter → createCurrentItem() → feedback, clear (stays open)
  → Backspace on empty → clearForcedType()

Command mode (activated via slash-picker)
  → /today → today's reminders list
  → /recent or /r → all notes+reminders timeline
  → /search or /s [query] → search results
  → Esc → returns to capture; if note selected in detail → back to capture
```

### Autosave (keystroke debounce)

For note-type input only (not reminders, not slash commands):
- Each `inputText` change schedules a 0.8 s debounced Task.
- On fire: calls `persistCurrentNoteDraftImmediately()` → `saveCurrentInputAsNoteDraft(showFeedback: false)`.
- The same `sessionNoteId` UUID is reused for the entire open session so edits update the same note.
- On close: `commitSession()` runs synchronously and `lastDismissDate` is recorded.
- If reopened within 5 minutes with non-empty input: grace-period restore — shows "Note saved" feedback and keeps current input.

### NLP type detection

On every `inputText` change, `detectType()` runs:
- Contains "remind me", "remember to", or "don't forget" → `detectedType = .reminder`
- Else → `detectedType = .note`

Forced-type overrides this entirely. The detected type controls whether the bottom type badge and autosave behavior treat input as note or reminder.

---

## Commands and Slash Picker

Typing `/` alone opens `JottSlashCommandPicker` — a grid of command tiles. Selecting one calls `activateCommandMode(_:)` which sets `viewModel.commandMode`. Once a command mode is active, the slash badge renders in the input bar and `inputText` is treated as the query for that command.

Switching commands: typing `/` again while in command mode sets `isTypingNewCommand = true`. The current command list keeps rendering but the slash picker reappears in the suggestion bar.

Commands:

| Slash | Command | Behavior |
|---|---|---|
| /today or /t | `.today` | Upcoming reminders due today |
| /recent or /r | `.inbox` | All notes + reminders sorted by date |
| /search [q] or /s [q] | `.search(query:)` | Full-text search across notes + reminders |
| /calendar | `.calendar` | Entry creates Apple Calendar event via EventKit |
| /reminders | `.reminders(query:)` | Browse/create Apple Reminders |

Creation preview: when command mode is `.calendar` or `.reminders` (or forced reminder type) and input is non-empty, `commandCreationPreview()` returns a `(title, date, hasDate, recurrence)` tuple shown in `ItemCreationPreviewCard`. Cmd+Return (or Enter in creation preview) calls `createFromCommandMode()`.

---

## Detail View

When `viewModel.selectedNote != nil` or `viewModel.selectedReminder != nil`, `DetailView` renders instead of `JottCaptureView`. Transition: `.jottDetailIn` (slide-down 6 pt + scale 0.97 + opacity on insert; slide-up + scale + opacity on removal, all driven by `JottMotion.panel`).

Back navigation: Esc or a back button. If editing, `saveEditedNote()` is called before closing.

Subnote navigation: `openSubnote(_:)` pushes a `[parent, subnote]` stack. `popNavigation()` pops it. The stack is cleared on overlay close.

---

## Note Editing

Inline edit mode is triggered from detail view. `startEditingNote(_:)` copies blocks into `editingNoteBlocks`. The editor renders a `LibraryNoteTextEditor` (block-based). Changes autosave via `autoSaveEditedNote` (no debounce in the pill; 600 ms in the focus pill expanded editor).

Saving: `saveEditedNote(_:)` calls `cleanedNoteBlocks()` (filters empty blocks), then `store.upsertNote()`. If blocks are empty and the original also had no content, the note is permanently deleted rather than going to trash.

---

## Data Model

### Note

```swift
id: UUID
blocks: [Block]       // source of truth
links: [UUID]         // backlink references
tags: [String]
timestamp: Date       // created
modifiedAt: Date
isPinned: Bool
clusterId: UUID?
parentId: UUID?       // subnote parent
sortIndex: Int        // explicit ordering within parent
folderId: UUID?
deletedAt: Date?      // nil = active, non-nil = in trash
```

`text` is a computed compatibility shim: getter = `blocks.map(\.plainText).joined(separator:"\n")`, setter = `Block.plainTextBlocks(from:)`.

### Block

```swift
type: BlockType       // paragraph | heading | bulletItem | numberedItem |
                      // taskItem | quote | codeBlock | table | divider |
                      // image | toggle
spans: [TextSpan]     // rich text runs
level: Int            // heading level 1–3
checked: Bool         // taskItem state
tableHeaders: [String]
tableRows: [[String]]
language: String?     // codeBlock
code: String
imageURL: String?
imageAlt: String
children: [Block]
props: [String:String]
```

### TextSpan

```swift
text: String
bold, italic, underline, code, strikethrough, highlight: Bool
linkURL: String?
noteRef: UUID?        // backlink
```

Marks encode as `["bold","italic","inline_code",...]` array in JSON. Legacy flat-bool format is decoded for backwards compatibility.

### Storage

- One `.jott` file per note in the notes folder (default: `~/Library/Application Support/com.casualhermit.jott/jott-notes/`).
- File content: `{"blocks":[...],"links":[...]}` — no metadata in file.
- Metadata sidecar: `notes-meta.json` in app support. Maps UUID → `{tags, isPinned, clusterId, parentId, folderId, created, modified, filename, deletedAt}`.
- Filename = slug of note title (max 50 chars, hyphenated). Deduplicated with counter suffix.
- Subdirectories for folders. Folder structure mirrored on disk as slugified path components.
- On folder rename/delete: notes are moved on disk.
- Legacy `.md` files (frontmatter or body-only) are migrated to `.jott` on first read and the `.md` is deleted.
- Legacy `notes.json` (single-file store) migrated on first launch.
- Auto-refresh every 45 seconds via timer + on app activation + on CloudKit push notification.
- Soft delete: `deletedAt` is set; note stays in file and meta. Purged after 30 days.

### Folders and Clusters

Folders: `NoteFolder` structs with name, colorTag, parentId. Persisted in `folders.json`. Up to arbitrary depth. Notes can be moved between folders; file moves on disk.

Clusters: `Cluster` structs. Persisted in `clusters.json`. Used by the graph/canvas views for grouping.

---

## Sync

`CloudKitSyncManager.shared` handles iCloud sync. Notes, folders, and attachments are pushed on every `upsertNote`/`upsertFolder` call. Remote push notifications trigger `refreshFromDisk()`. CKSubscription is set up on launch.

---

## Clipboard Monitor

`ClipboardMonitor.shared` polls the pasteboard on a timer and records the most recent text or image kind. On overlay open, `viewModel.pendingClipboardKind` and `pendingClipboardText` are populated from the snapshot. The toolbar shows a "Use clipboard" / "Use image" chip. Accepting calls `textView.insertTransfer(from: NSPasteboard.general)` which handles both text and image paste inline.

---

## Speech Input

`SpeechManager.shared` wraps `SFSpeechRecognizer`. Microphone button in the floating actions row. During recording, a `VoiceWaveformPill` renders animated bars at the current audio level. Partial transcriptions update `inputText` in real time. Final transcription commits. Voice prefix (text already in input before recording) is prepended.

---

## Appearance

Always dark mode for the overlay panel (`NSAppearance.darkAqua` applied explicitly to panel, content view, and hosting view). Light/dark toggle in menu bar dropdown applies to `UserDefaults("jott_darkMode")` and `NSApp.appearance`.

### Color tokens

| Token | Light | Dark |
|---|---|---|
| `jottOverlaySurface` | rgba(246,247,245, 0.58) | rgba(21,23,29, 0.84) |
| `jottOverlaySurfaceElevated` | rgba(250,250,248, 0.68) | rgba(27,29,35, 0.88) |
| `jottNotchVoidBlack` | — | calibratedWhite 0.015 |
| `jottOverlaySky` | rgb(88,167,237) | same |
| `jottOverlayMintAccent` | rgb(107,219,186) | same |
| `jottOverlayPeachAccent` | rgb(252,172,143) | same |

### Typography

All UI text uses `.system(design: .rounded)` via `JottTypography`:
- UI labels: 13 pt regular
- Note titles: 15 pt medium
- Note body: 12.5 pt regular
- Keyboard hints: 10 pt monospaced medium

### Animation constants (`JottMotion`)

| Constant | Value | Use |
|---|---|---|
| `.panel` | `spring(response:0.24, dampingFraction:0.88)` | Card transitions, scene changes |
| `.content` | `easeOut(duration:0.14)` | Status chips, badge reveals, dropdown fade |
| `.micro` | `spring(response:0.14, dampingFraction:0.86)` | Button press, hover fills |
| `.connect` | `spring(response:0.42, dampingFraction:0.80)` | Graph node repositioning |

### Transitions

| Transition | Insert | Remove |
|---|---|---|
| `.jottCaptureIn` | scale 0.97 + opacity, `.panel` | scale 0.985 + opacity, `.content` |
| `.jottDetailIn` | offset y+6 + scale 0.97 from top + opacity, `.panel` | offset y-4 + scale + opacity, `.content` |
| `.jottDetailSwap` | offset x+4 + opacity, `.content` | opacity, `.content` |
| `.jottDropdown` | scale 0.97 from top + offset y+6 + opacity, `.panel` | scale 0.985 + offset y-4 + opacity, `.content` |
| `.jottToolbarReveal` | scale 0.96 from trailing + opacity, `.content` | scale 0.98 + opacity, `.content` |

### Button styles

`JottSquishyButtonStyle(pressedScale:, pressedOpacity:)` — springs to pressed scale on press, returns on release. `micro` animation.

---

## Settings

`JottSettingsView` opened as a SwiftUI `Window` scene (id: `jott-settings`), 420 × 320 pt.

Settings stored in `UserDefaults`:
- `jott_darkMode` — Bool
- `jott_overlayPosition` — String (currently always "center"; reserved for future positioning)
- `jott_notesFolderBookmark` — Data (security-scoped bookmark for custom notes folder)
- `jott_hasSeenWelcome` — Bool

---

## Library View

`LibraryWindowController` wraps `LibraryView` in a standard titled window. Shows all notes in a sidebar+detail layout. Uses the same `OverlayViewModel` instance so note edits stay in sync.

---

## Focus Note

`viewModel.focusedNote: Note?` — when set, the pill appears. Set by:
- Pinning a note from detail view
- Tapping the pin icon on the pill itself unpins (sets to nil)
- Tapping the open-note icon on the pill expands the pill

The expanded pill (`FocusPillExpandedContent`) contains a `LibraryNoteTextEditor` for inline editing and a subnotes section. Autosaves 600 ms after changes.

---

## Subnotes

Notes with `parentId != nil` are subnotes. They are hidden from the main inbox (`getAllNotes()` filters `parentId == nil`). Subnotes appear in the detail view's `SubnoteOutlinerView`. Search includes subnotes (shows parent breadcrumb). `sortIndex` enables explicit ordering within a parent.

Subnote session: `OverlayViewModel` tracks `subnoteSessionId`/`subnoteSessionParentId` to reuse the same UUID while auto-saving as the user types. `commitSubnoteDraft()` seals the draft (new UUID for next entry). `discardSubnoteDraft()` deletes empty drafts.

---

## Reminders

Reminders are stored in `reminders.json` (local) and optionally synced to Apple Reminders via EventKit. `NotificationManager` schedules `UNUserNotificationCenter` notifications for due reminders. Snooze updates both stores.

---

## Telemetry and Crash Reporting

`Telemetry` = Sentry wrapper. `Telemetry.start()` called at launch. Breadcrumbs added at lifecycle events. NLP parse failures logged with `Telemetry.recordNLPParseFailure`.

---

## In-App Purchase

`PurchaseManager.shared` wraps RevenueCat (API key set in `jottApp.init`). `PaywallView` shown via `NotificationCenter.jottShowPaywall` post. `PurchaseManager` is `@StateObject` in `UnifiedJottView`.

---

## Key Constraints and Edge Cases

- **Notch detection**: `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` used on macOS 12+. Falls back to `midX ± 77 pt` on older systems or non-notch screens.
- **Frame management**: No SwiftUI auto-resize of panels. `FirstMouseHostingView.intrinsicContentSize = .zero` + no-op `windowDidLayout` are load-bearing. Removing either causes layout loops.
- **Mouse event suppression during frame animation**: Pill uses `panel.ignoresMouseEvents = true` during `NSAnimationContext` to prevent `onHover` oscillation from SwiftUI tracking areas.
- **Hover oscillation**: Pill hover state is suppressed inside `onHover` when `pillState.isExpanded` — avoids state thrashing during expand animation.
- **Single-click into overlay**: `acceptsFirstMouse` override enables first-mouse interaction without requiring a pre-click to focus the window.
- **Resign-key dismiss**: `OverlayPanel.resignKey()` posts `overlayDidResignKey` unless the mouse is within an 8 pt inset of the panel frame, or `suppressResignKey` is set (drag operations), or `isLocked` is true.
- **Grace period**: If dismissed within 5 minutes and input was non-empty, re-opening does not clear the draft — saves a double-open to continue a thought.
- **Empty note cleanup**: `deleteNoteIfEmpty(_:)` permanently deletes (no trash) a note whose text is blank. Used in editing paths to avoid accumulating untitled ghosts.
- **Deduplication**: `dedupeNotesCache()` runs after every load to keep only the most-recently-modified copy when UUID collisions arise (e.g. from CloudKit merge conflicts).
