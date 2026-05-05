# Jott Developer Reference

This document is a practical map of the Jott codebase. It is intended for developers who need to understand where product behavior lives, which files own which responsibilities, and how the main UI, UX, state, persistence, and integrations fit together.

This is not an implementation guide and intentionally avoids code snippets. Use it as a starting point before changing behavior.

## Product Overview

Jott is a macOS menu-bar capture app for quick notes, reminders, calendar-aware capture, search, and library review.

The product is built around one fast capture surface called the Jott bar. The bar should feel like a minimal text-first input by default. Richer UI appears only when the user's intent requires it, such as slash commands, search, today views, tag completion, smart recall, calendar results, or help.

Core principles:

- The default state is plain writing, not browsing.
- The dropdown is contextual and should not always be visible.
- Enter and Shift+Enter are writing actions and insert a new line.
- Cmd+Enter is the explicit create, open, or save action.
- Tab is the navigation/open action inside command and recall results.
- Notes should autosave while typing when the input is clearly a note draft.
- Commands should remain fast, keyboard-first, and visually minimal.

## Main Architecture

Jott is a SwiftUI macOS app with AppKit bridges for global hotkeys, panel behavior, native text editing, window control, EventKit, file persistence, and menu-bar lifecycle.

The most important runtime path is:

1. `jottApp.swift` starts the app, menu bar, delegate, hotkey manager, and window controllers.
2. `HotkeyManager.swift` listens for the global shortcut and toggles the overlay.
3. `OverlayWindowController.swift` owns the floating panel and hosts the SwiftUI overlay.
4. `OverlayViewModel.swift` owns capture state, commands, persistence decisions, selection state, and view lifecycle.
5. `UnifiedJottView.swift` renders the Jott bar, dropdowns, command results, input behavior, badges, and detail switching.
6. `NoteStore.swift` persists notes, reminders, folders, clusters, attachments, and opens files/folders.

## Directory Map

| Path | Purpose |
| --- | --- |
| `jott/` | Main macOS application source. |
| `jott/Model/` | Data models, persistence, parsing, search, AI, clipboard, speech, calendar/reminders, notifications, telemetry, and updates. |
| `jott/ViewModel/` | Application state and business flow for the overlay. |
| `jott/Views/` | SwiftUI views for the overlay, library, details, settings, graph/canvas views, and older/simple views. |
| `jott/Window/` | AppKit window and panel controllers. |
| `jott/Hotkey/` | Global hotkey registration and event handling. |
| `jott/Extensions/` | Shared visual system helpers, colors, blur, motion, typography, and reusable styling. |
| `jottTests/` | XCTest coverage for parser, note store, and clipboard monitor behavior. |
| `docs/` | Product and developer documentation. |

## App Shell And Lifecycle

| File | Primary Responsibility |
| --- | --- |
| `jott/jottApp.swift` | App entry point, menu-bar UI, app delegate, launch lifecycle, shared stores, overlay/library/settings wiring, quit behavior. |
| `jott/ContentView.swift` | Simple root content placeholder or legacy root view. Not the primary app experience. |
| `jott/Hotkey/HotkeyManager.swift` | Global keyboard shortcut registration and shortcut event dispatch. |
| `jott/Window/OverlayWindowController.swift` | Floating overlay panel creation, hosting, placement, animation, open/close behavior, dark/light appearance handling. |
| `jott/Window/OverlayPanel.swift` | Custom `NSPanel` behavior for the capture overlay, including focus/resign handling. |
| `jott/Window/LibraryWindowController.swift` | Separate AppKit window controller for the library/settings style window. |

Lifecycle notes:

- The menu bar is the long-lived app surface.
- The overlay is transient and controlled through `OverlayWindowController`.
- `OverlayViewModel.show()` prepares a new capture session or restores a recent one inside the grace period.
- `OverlayViewModel.dismiss()` commits valid input, cancels transient tasks, clears selections, and hides the overlay.
- Library and settings are separate from the capture overlay and should not own capture-session behavior.

## Core State And Business Logic

| File | Primary Responsibility |
| --- | --- |
| `jott/ViewModel/OverlayViewModel.swift` | Central state machine for capture, commands, notes, reminders, meetings, detail selection, autosave, clipboard prefill, calendar import, tag filtering, inline editing, subnotes, and overlay lifecycle. |

Important responsibilities in `OverlayViewModel.swift`:

- Tracks current input text and detected type.
- Strips forced creation prefixes such as note/reminder intent prefixes.
- Detects whether content should be a note or reminder.
- Schedules note autosave when typing a normal note draft.
- Commits the current session on explicit create or dismiss.
- Maintains selected note, reminder, or meeting for detail mode.
- Computes command-mode result lists.
- Handles smart recall search over notes, subnotes, and reminders.
- Handles active tag filters and tag completion.
- Creates notes, reminders, checklist notes, EventKit reminders, and calendar events.
- Imports calendar events into meeting records.
- Saves inline edits and note detail edits.
- Creates, autosaves, commits, and discards subnote drafts.

State ownership rule:

- If behavior changes what the app does with user intent, it usually belongs in `OverlayViewModel.swift`.
- If behavior changes how the Jott bar looks or how input keys are interpreted, it usually belongs in `UnifiedJottView.swift`.
- If behavior changes persistence, file layout, markdown conversion, folders, or attachments, it usually belongs in `NoteStore.swift`.

## Capture UI And UX

| File | Primary Responsibility |
| --- | --- |
| `jott/Views/UnifiedJottView.swift` | Main overlay UI, Jott bar, native text editor bridge, command suggestions, command result dropdowns, smart recall, today view, calendar view, welcome/help surfaces, note cards, rows, badges, formatting bar, drag/drop, keyboard behavior. |
| `jott/Views/OverlayView.swift` | Older/simple overlay composition. Not the primary current Jott bar implementation. |
| `jott/Views/CaptureInputView.swift` | Older/simple capture input view. Not the primary current input implementation. |
| `jott/Views/InputOnlyView.swift` | Minimal older/simple input-only view. |
| `jott/Views/SaveConfirmationView.swift` | Save feedback surface. |

Primary UI pieces inside `UnifiedJottView.swift`:

| Component | Purpose |
| --- | --- |
| `UnifiedJottView` | Chooses between capture mode and detail mode. |
| `JottCaptureView` | Main overlay layout: input row, mic button, dropdown area, command results, help/welcome states. |
| `JottInputArea` | Text input shell, type badge, placeholder hints, active tag chip, voice button integration. |
| `JottNativeInput` | SwiftUI to AppKit bridge for native text input. |
| `JottNSTextView` | Native text editing, keyboard commands, markdown attachment round-trip, ghost text, formatting shortcuts. |
| `JottCommand` | Slash command model and command parsing. |
| `JottCommandSuggestionBar` | Minimal command badge rail. |
| `CommandRailButton` | Individual squircle command badge. |
| `JottCommandResults` | Command dropdown result list/grid. |
| `SmartRecallView` | Contextual recall results based on typed text. |
| `JottTodayView` | Today-focused notes/reminders/calendar surface. |
| `CalendarResultsView` | Upcoming calendar event list and import entry point. |
| `ItemCreationPreviewCard` | Preview for creating dated reminders or events from typed text. |
| `JottTagSuggestionView` | Tag autocomplete dropdown. |
| `JottWelcomeCard` | First-run welcome state. |
| `JottHelpPopover` | Help and shortcut surface. |
| `JottFormatBar` | Formatting controls for selected text. |
| `JottNoteCard` and `JottRow` | Result and note rendering primitives used by command views. |

Current Jott bar UX:

- The input is the primary surface.
- Dropdown content is hidden by default.
- The dropdown appears for slash commands, command results, smart recall, tag completion, help, item creation preview, today, calendar, inbox, open actions, and first-run welcome.
- There is no always-on default today dropdown.
- Command badges use compact squircle styling, not large pills.
- Icons are minimal and should not rely on heavy backgrounds.
- The visual system uses a darker overlay tint and restrained contrast.

Current keyboard model:

| Key | Behavior |
| --- | --- |
| Enter | Insert a new line. If the current line is a list item, continue the list marker where appropriate. |
| Shift+Enter | Insert a new line with the same writing behavior as Enter. |
| Cmd+Enter | Create current item, open selected result, or save inline edit depending on context. |
| Tab | Complete command text, accept ghost text, open selected command/smart recall item, or cycle type depending on context. |
| Up/Down | Move selection in command results, smart recall, or relevant dropdowns. |
| Escape | Close dropdown/detail state first, then dismiss overlay when appropriate. |
| Cmd+B/I/U/E | Text formatting shortcuts in the native editor. |
| Cmd+Shift+F | Toggle formatting controls. |
| Cmd+Shift+M | Toggle voice capture. |
| Cmd+Shift+K | Clear active tag filter. |
| Cmd+Shift+X | Clear clipboard prefill. |

Design rule:

- Do not make Enter create or open items. Enter is for writing. Use Cmd+Enter or Tab for action-oriented behavior.

## Commands And Discovery

Command behavior is split between `UnifiedJottView.swift` and `OverlayViewModel.swift`.

| Area | File | Responsibility |
| --- | --- | --- |
| Command definitions and aliases | `jott/Views/UnifiedJottView.swift` | Defines command cases, labels, icons, matching, and display metadata. |
| Command result computation | `jott/ViewModel/OverlayViewModel.swift` | Returns notes, reminders, search results, today items, inbox items, open actions, and calendar-driven items. |
| Command result rendering | `jott/Views/UnifiedJottView.swift` | Renders dropdowns, sections, cards, rows, previews, and selection states. |
| Command item creation | `jott/ViewModel/OverlayViewModel.swift` | Creates notes, reminders, and calendar events from command mode. |

Current command families:

| Command Family | Purpose |
| --- | --- |
| Notes | Browse or search notes. |
| Search | Search across notes and reminders. |
| Today | Show today's relevant notes/reminders/calendar context. |
| Reminders | Browse or create reminder-oriented items. |
| Calendar | Show upcoming events and allow event import. |
| Inbox | Show recent mixed capture items. |
| Open | Show quick app/navigation actions. |

Dropdown rule:

- Slash command mode is intentional browsing.
- Non-command typing should stay focused on writing unless smart recall, tags, help, or preview is relevant.

## Notes, Reminders, Meetings, And Folders

| File | Primary Responsibility |
| --- | --- |
| `jott/Model/Note.swift` | Note data model, including text, tags, pin state, parent/subnote relationships, timestamps, and codable support. |
| `jott/Model/Reminder.swift` | Reminder data model with due date, completion state, tags, and codable support. |
| `jott/Model/Meeting.swift` | Meeting data model used for imported calendar events and meeting detail surfaces. |
| `jott/Model/NoteFolder.swift` | Folder model and folder color metadata. |
| `jott/Model/Cluster.swift` | Cluster/canvas grouping model for visual organization. |

Model ownership notes:

- Notes are the default content type.
- Reminders are created from natural-language reminder intent, forced reminder mode, or command mode.
- Meetings are generally created by importing calendar events rather than freeform capture.
- Folders organize notes in the library.
- Subnotes are regular notes with a parent note relationship.

## Persistence And Local Data

| File | Primary Responsibility |
| --- | --- |
| `jott/Model/NoteStore.swift` | Main local persistence layer for notes, reminders, folders, clusters, attachments, markdown files, security-scoped notes folder bookmarks, cache loading, saving, deletion, file opening, and folder opening. |

Storage responsibilities:

- Notes are stored as Markdown files in the selected notes folder.
- A security-scoped bookmark is used when the user selects a custom notes folder.
- The app falls back to an Application Support notes folder when no custom folder is selected.
- Attachments are stored in an attachments directory under the notes folder.
- Reminders, folders, and clusters are stored in app support JSON files.
- `NoteStore` maintains filename mappings so note files can use readable slugs while preserving stable note IDs.
- `NoteStore` exposes app-facing operations for adding, updating, deleting, listing, and opening notes.

Change rule:

- Any change to file layout, markdown serialization, attachment paths, bookmark handling, note naming, folder persistence, or reminder persistence should start in `NoteStore.swift`.

## Natural Language And Search

| File | Primary Responsibility |
| --- | --- |
| `jott/Model/NaturalLanguageParser.swift` | Parses user text into note/reminder/event intent, extracts dates, times, recurrence, checklist patterns, hashtags, and event titles. |
| `jott/Model/SearchEngine.swift` | Search result types and search behavior across notes/reminders. |

Natural-language responsibilities:

- Detects reminder phrases.
- Extracts relative dates such as today, tomorrow, weekdays, and next week.
- Extracts times and absolute dates.
- Extracts recurrence such as daily, weekly, monthly, yearly, and every-N intervals.
- Extracts hashtags.
- Detects checklist-style input and converts it into note content.
- Parses event-like text for command-driven reminders and calendar events.

Search responsibilities:

- Supports result modeling for notes/reminders.
- Provides reusable search behavior separate from UI rendering.
- Overlay smart recall also performs lightweight matching in `OverlayViewModel.swift`.

## Calendar, Reminders, Voice, Clipboard, Notifications, AI

| File | Primary Responsibility |
| --- | --- |
| `jott/Model/CalendarManager.swift` | EventKit calendar/reminders permissions, selected calendar/list persistence, upcoming event fetches, reminder creation, calendar event creation, privacy settings links. |
| `jott/Model/SpeechManager.swift` | Speech recognition state, voice capture, audio level, and transcript flow. |
| `jott/Model/ClipboardMonitor.swift` | Tracks recently copied text and provides one-time clipboard prefill into the overlay. |
| `jott/Model/NotificationManager.swift` | Local notification scheduling and reminder notification behavior. |
| `jott/Model/NoteAIService.swift` | AI-backed note assistance, suggestions, autocomplete/corpus logic, and related async behavior. |
| `jott/Model/CrashReporter.swift` | Telemetry level, breadcrumbs, error capture, and diagnostic messages. |
| `jott/Model/UpdateManager.swift` | App update checking and update state. |

Integration notes:

- EventKit access is split between calendar events and reminders permissions.
- Settings should expose permission and calendar/list choices through `JottSettingsView.swift`.
- Clipboard prefill should be consumed once so it does not repeatedly overwrite the user's input.
- Voice capture belongs in the input experience, but speech recognition state belongs in `SpeechManager.swift`.
- AI features should remain optional and should not block basic note capture.

## Detail And Editing UI

| File | Primary Responsibility |
| --- | --- |
| `jott/Views/DetailView.swift` | Detail mode for notes, reminders, and meetings; rich markdown-ish note rendering; attachments; video/link cards; inline editor; edit toolbar; note metadata; reminder actions; meeting details. |
| `jott/Views/SubnoteOutlinerView.swift` | Subnote list, subnote cards, add-subnote row, and native subnote text editor. |

Detail behavior:

- Selecting a note, reminder, or meeting moves the overlay from capture mode into detail mode.
- Note detail supports reading, editing, rich content display, attachments, links, and metadata.
- Reminder detail supports due-date and completion-style actions.
- Meeting detail displays imported calendar event context.
- Subnotes are edited through dedicated subnote UI but persisted through `OverlayViewModel` and `NoteStore`.

Ownership rule:

- If a change affects the selected item's detail screen, start in `DetailView.swift`.
- If a change affects subnote rows or subnote input behavior, start in `SubnoteOutlinerView.swift`.
- If a change affects saving detail edits, check `OverlayViewModel.swift` and `NoteStore.swift`.

## Library UI

| File | Primary Responsibility |
| --- | --- |
| `jott/Views/LibraryView.swift` | Main library window: filters, display modes, folder views, note/reminder selection, search, detail panel, delete confirmation, top bar, stats, empty states, AI inline editor, inspector panels. |

Library features:

- Browse notes and reminders outside the transient overlay.
- Switch between filter modes.
- Search notes/reminders.
- Show folder cards and folder empty states.
- Create, rename, and use folders.
- Inspect selected notes/reminders.
- Delete with confirmation.
- Show timeline-style items.
- Provide AI-assisted inline editing surfaces.

Ownership rule:

- Library-only interaction should live in `LibraryView.swift`.
- Shared data changes should still go through `NoteStore.swift` or `OverlayViewModel.swift` as appropriate.

## Visual System

| File | Primary Responsibility |
| --- | --- |
| `jott/Extensions/Color+Jott.swift` | Shared color tokens and overlay/library tint values. |
| `jott/Extensions/View+VisualEffect.swift` | Visual effect blur, ambient backdrop, glass panel background, motion constants, typography constants, button styles, hover spotlight modifier. |

Visual principles:

- Keep the Jott bar darker, quieter, and minimal.
- Prefer text-first hierarchy over icon-heavy UI.
- Use squircle badges/buttons where command surfaces need shape.
- Avoid large pill-heavy controls unless the surrounding UI intentionally uses that language.
- Icons should usually be line icons without standalone decorative backgrounds.
- Motion should communicate entry, focus, or state transition without becoming noisy.

Change rule:

- Global color, blur, typography, and motion changes should start in `Extensions`.
- One-off layout or state-specific visual changes should stay near the owning view.

## Graph, Canvas, Radar, And Visual Organization

| File | Primary Responsibility |
| --- | --- |
| `jott/Views/GraphCanvasView.swift` | Graph-style visual canvas, cluster frames, graph nodes, breadcrumbs. |
| `jott/Views/ClusterCanvasView.swift` | Cluster canvas layout, draggable/organized node surfaces, sidebar, divider, canvas node rendering. |
| `jott/Views/NoteGraphViews.swift` | Network graph view and graph node buttons for note relationships. |
| `jott/Views/RadarView.swift` | Radar-style visual display with center card and spoke nodes. |
| `jott/Model/Cluster.swift` | Persisted grouping model used by canvas/cluster features. |

These views are separate from the core Jott bar capture flow. Treat them as visual organization surfaces backed by note and cluster data.

## Settings

| File | Primary Responsibility |
| --- | --- |
| `jott/Views/JottSettingsView.swift` | Settings UI for calendar/reminders permissions, selected calendar/list, notes folder, overlay position, command suggestions, and AI context settings. |

Settings behavior:

- Settings should configure integrations and preferences.
- Settings should not directly implement capture behavior.
- If settings change a stored preference, verify the runtime owner reads from the same source.

## Legacy Or Secondary Views

Some views remain in the codebase as older/simple surfaces or secondary flows:

| File | Current Role |
| --- | --- |
| `jott/Views/OverlayView.swift` | Older overlay wrapper. |
| `jott/Views/CaptureInputView.swift` | Older simple capture input. |
| `jott/Views/InputOnlyView.swift` | Minimal input-only surface. |
| `jott/Views/RemindersListView.swift` | Simple reminders list. |
| `jott/Views/MeetingsListView.swift` | Simple meetings list. |
| `jott/Views/SaveConfirmationView.swift` | Standalone save confirmation UI. |

Before deleting or heavily refactoring these files, search for current references. Some may still be used by previews, alternate routes, or older window flows.

## Feature Inventory

| Feature | Primary Files |
| --- | --- |
| Menu-bar app lifecycle | `jottApp.swift`, `HotkeyManager.swift`, `OverlayWindowController.swift` |
| Global overlay shortcut | `HotkeyManager.swift`, `OverlayWindowController.swift`, `OverlayViewModel.swift` |
| Jott bar capture UI | `UnifiedJottView.swift`, `OverlayViewModel.swift` |
| Contextual dropdown visibility | `UnifiedJottView.swift` |
| Slash commands | `UnifiedJottView.swift`, `OverlayViewModel.swift` |
| Command result navigation | `UnifiedJottView.swift`, `OverlayViewModel.swift` |
| Plain note capture | `OverlayViewModel.swift`, `NoteStore.swift`, `NaturalLanguageParser.swift` |
| Note autosave while typing | `OverlayViewModel.swift`, `NoteStore.swift` |
| Reminder capture | `OverlayViewModel.swift`, `NaturalLanguageParser.swift`, `CalendarManager.swift`, `NoteStore.swift` |
| Calendar event creation | `OverlayViewModel.swift`, `NaturalLanguageParser.swift`, `CalendarManager.swift` |
| Calendar event import | `OverlayViewModel.swift`, `CalendarManager.swift`, `Meeting.swift` |
| Smart recall | `OverlayViewModel.swift`, `UnifiedJottView.swift` |
| Tag autocomplete and filtering | `OverlayViewModel.swift`, `UnifiedJottView.swift`, `NoteStore.swift` |
| Markdown-like formatting | `UnifiedJottView.swift`, `DetailView.swift` |
| Attachments and image round-trip | `UnifiedJottView.swift`, `DetailView.swift`, `NoteStore.swift` |
| Detail reading/editing | `DetailView.swift`, `OverlayViewModel.swift`, `NoteStore.swift` |
| Subnotes | `SubnoteOutlinerView.swift`, `OverlayViewModel.swift`, `NoteStore.swift`, `Note.swift` |
| Library window | `LibraryWindowController.swift`, `LibraryView.swift`, `NoteStore.swift` |
| Folders | `LibraryView.swift`, `NoteStore.swift`, `NoteFolder.swift` |
| Graph/canvas organization | `GraphCanvasView.swift`, `ClusterCanvasView.swift`, `NoteGraphViews.swift`, `RadarView.swift`, `Cluster.swift` |
| Voice capture | `UnifiedJottView.swift`, `SpeechManager.swift` |
| Clipboard prefill | `OverlayViewModel.swift`, `ClipboardMonitor.swift` |
| Notifications | `NotificationManager.swift`, `Reminder.swift` |
| AI assistance | `NoteAIService.swift`, `LibraryView.swift`, `DetailView.swift` |
| Settings | `JottSettingsView.swift`, `CalendarManager.swift`, `NoteStore.swift`, `OverlayViewModel.swift` |
| Telemetry and diagnostics | `CrashReporter.swift` |
| Updates | `UpdateManager.swift` |

## Data Flow By User Action

### Open Jott Bar

1. Global shortcut or menu-bar action triggers the overlay controller.
2. `OverlayViewModel.show()` prepares the session.
3. Clipboard prefill may populate the input once.
4. `UnifiedJottView` renders the capture state.

### Type A Plain Note

1. User types into `JottNSTextView`.
2. Text binding updates `OverlayViewModel.inputText`.
3. Type detection keeps the draft as a note unless reminder intent is detected.
4. Autosave schedules a short delayed save for normal note drafts.
5. `NoteStore` writes or updates the Markdown note.
6. Dismiss or Cmd+Enter commits the final session state.

### Type A Slash Command

1. User types a slash command.
2. `UnifiedJottView` parses the command family and query.
3. `OverlayViewModel` provides matching command items.
4. `UnifiedJottView` renders the dropdown.
5. Up/Down changes selection.
6. Tab opens the selected item or completes command text.
7. Cmd+Enter performs create/open/save behavior for the current context.

### Create A Reminder

1. User types reminder intent, forced reminder mode, or reminder command text.
2. `NaturalLanguageParser` extracts title, date, tags, and recurrence.
3. `OverlayViewModel` creates the local reminder model.
4. `NoteStore` persists the reminder.
5. `CalendarManager` attempts EventKit reminder creation when permissions allow it.

### Create A Calendar Event

1. User enters calendar command mode.
2. `NaturalLanguageParser` extracts event title, date, and recurrence.
3. `OverlayViewModel` requests event creation.
4. `CalendarManager` writes to the selected EventKit calendar when authorized.

### Open Detail

1. User selects a note, reminder, or meeting from a dropdown/library.
2. `OverlayViewModel` sets the selected item.
3. `UnifiedJottView` switches from capture mode to `DetailView`.
4. Saves and edits flow back through `OverlayViewModel` and `NoteStore`.

### Use Library

1. User opens the library window.
2. `LibraryWindowController` hosts `LibraryView`.
3. `LibraryView` queries `NoteStore` and local UI state for lists, filters, folders, search, and inspectors.
4. Mutations go through store-backed operations.

## Testing Map

| Test File | Coverage Area |
| --- | --- |
| `jottTests/NaturalLanguageParserTests.swift` | General parser behavior. |
| `jottTests/NaturalLanguageParserDateTests.swift` | Date parsing behavior. |
| `jottTests/NoteStoreTests.swift` | Store and persistence behavior. |
| `jottTests/ClipboardMonitorTests.swift` | Clipboard monitor behavior. |

Recommended validation for behavior changes:

- Parser changes should add or update parser tests.
- Persistence changes should add or update note store tests.
- Clipboard behavior changes should update clipboard monitor tests.
- UI keyboard behavior should be manually verified in the macOS app because much of it depends on AppKit text view behavior.
- Build validation should use the project scheme before handing off substantial changes.

## Where To Change Common Things

| Change Needed | Start Here |
| --- | --- |
| Add or rename a slash command | `UnifiedJottView.swift`, then `OverlayViewModel.swift` for behavior. |
| Change when the dropdown appears | `UnifiedJottView.swift`. |
| Change Enter, Tab, Escape, or Cmd+Enter behavior | `UnifiedJottView.swift`, especially the native text view bridge and coordinator. |
| Change note autosave rules | `OverlayViewModel.swift`. |
| Change final save/commit behavior | `OverlayViewModel.swift`. |
| Change note file format or filenames | `NoteStore.swift`. |
| Change reminder date parsing | `NaturalLanguageParser.swift`. |
| Change EventKit reminder/calendar behavior | `CalendarManager.swift`. |
| Change detail note rendering | `DetailView.swift`. |
| Change library layout or filters | `LibraryView.swift`. |
| Change global tint, blur, or shared button style | `Color+Jott.swift` and `View+VisualEffect.swift`. |
| Change settings UI | `JottSettingsView.swift`. |
| Change graph/canvas views | `GraphCanvasView.swift`, `ClusterCanvasView.swift`, `NoteGraphViews.swift`, or `RadarView.swift`. |

## Maintenance Notes

- Keep capture behavior centralized. Avoid duplicating save/create logic directly inside views unless it is strictly UI glue.
- Keep the Jott bar text-first. A dropdown should be earned by user intent.
- Preserve the current keyboard contract unless intentionally changing the product model.
- Prefer adding parser tests before changing natural-language behavior.
- Do not make AI, calendar, reminders, or clipboard integrations block basic note capture.
- Be careful when editing `UnifiedJottView.swift`; it owns many nested UI components and native AppKit bridge behavior in one file.
- Be careful when editing `NoteStore.swift`; it owns user data on disk.
- If a file looks legacy, search references before removing it.
