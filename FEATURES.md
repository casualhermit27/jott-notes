# Jott Notes — Complete Feature & UI/UX Reference

---

## App Shell

- **Menubar-only app** — no Dock icon, lives entirely in the menu bar
- **Global hotkey** `Option+Space` — opens/closes the overlay from anywhere
- **Floating panel** — 520×420pt transparent NSPanel, centers on active screen at ~38% from top
- **Fade animation** — 150ms ease-out in, 100ms ease-in out
- **Persistent dark/light mode** — toggled from menubar popover, saved to UserDefaults
- **Color scheme** applied globally — all views respect light/dark

---

## Capture Bar

### Input
- **Native NSTextView** (`JottNativeInput`) — full macOS text editing, cursor blink, selection
- **Custom cursor** — purple `#726bff`
- **Placeholder** — `#9d9d9d` grey, "Jott something..."
- **Multiline** — grows vertically with content
- **Enter** — creates/saves the current item (reminder/meeting/note)
- **Shift+Enter** — inserts a literal newline in the text
- **Escape** — dismisses the overlay

### Auto Type Detection
As you type, content is silently classified without any explicit command:
- **Note** — default, anything unrecognised
- **Reminder** — keywords: "remind me", "remember to", "don't forget"
- **Meeting** — keywords: "meeting with", "call with", "sync with", "standup", `@mention`
- **Checklist** — 2+ comma-separated short items (e.g. "buy milk, eggs, bread") → auto-converts to markdown checklist

### Tab → Cycle Type
When typing non-command content, **Tab** cycles the locked type:
`Note → Reminder → Meeting → Note`

### Type Badge (floating above bar, right)
- **Liquid morph animation** — squishes to 78%/55%, icon swaps at valley, springs back with color bleed
- **Note** — blue-grey gradient
- **Reminder** — orange/amber gradient
- **Meeting** — green/teal gradient
- Hides when bar is empty

### Floating Toolbar (above bar, right-aligned)
- **Feedback pill** — contextual message after save (see Feedback Loop below), springs in with bounce, fades after 2.5s
- **Aa button** — toggles format bar; accent tint when active
- **Format bar** — morphs left out of Aa button (scale from trailing anchor); Bold, Italic, Strikethrough, `Code`, Link, H1/H2/H3, Bullet, Numbered list, Quote
- All pills share bar background color (light: `#d9d9d9`, dark: `#1f1f24`)
- All pills have **1pt `strokeBorder`** — white 10% dark mode, black 9% light mode

### Bar Border
- 1pt `strokeBorder` on the main bar — same contrast values as pill borders, differentiates bar from same-color backgrounds

---

## Save Model

- **Save-on-dismiss** — saved when overlay closes, not while typing
- **Grace period restore** — reopen within 5 minutes restores previous unsaved text with feedback message
- **Session upsert** — each open session has a stable `UUID`; editing and re-dismissing updates the same note, no duplicates
- **Grace period expiry** — after 5 minutes, bar opens fresh and empty

---

## Action Engine

The bar understands *intent* and takes the right action automatically:

| Intent | Action |
|---|---|
| "remind me to pay rent tomorrow 8pm" | Creates reminder + schedules macOS notification + adds to Apple Reminders |
| "meeting with Ravi tomorrow at 3" | Saves meeting + creates Apple Calendar event |
| "buy milk, eggs, bread" | Converts to `- [ ]` checklist note |
| Plain text | Saves as note |

### Multiple Items in One Session
- After **Enter**, bar clears but stays open in the same type mode
- Type another reminder/meeting and hit Enter immediately — no dismissal needed
- Create unlimited reminders or meetings back-to-back

---

## Feedback Loop

Every action gives immediate, contextual confirmation in the floating pill:

| Action | Feedback |
|---|---|
| Reminder saved locally | `🔔 Reminder set · 8:00 PM` |
| Reminder → Apple Reminders | `🔔 Reminder → Apple Reminders · 8:00 PM` |
| Meeting saved locally | `📅 Meeting saved · 3:00 PM` |
| Meeting → Apple Calendar | `📅 Event → Apple Calendar · 3:00 PM` |
| Plain note | `📝 Note saved` |
| Checklist | `✅ Checklist · 3 items` |
| Grace period restore | Shows feedback + restores text |

---

## Command Mode

Triggered by typing `/`. Tab completes the highlighted suggestion.

| Command | Shorthand | What it does |
|---|---|---|
| `/notes` | `/n` | Browse & search all notes |
| `/reminders` | `/r` | Browse & search reminders |
| `/meetings` | `/m` | Browse & search meetings |
| `/search` | `/s` | Full-text search across all content |
| `/inbox` | `/i` | Unified timeline — all types sorted by latest |
| `/calendar` | `/cal` | Date/time picker for reminders & meetings |

### Forced Creation Mode
- Typing `/note `, `/reminder `, or `/meeting ` (with space) **locks** the type and strips the prefix
- Live **creation preview card** appears below the bar for Reminder and Meeting — shows NLP-parsed title + date
- Enter creates the item, clears input, stays open for another
- Backspace on empty clears the locked type back to normal

### Command Switching
- While in a command mode, typing `/` shows the suggestion bar for switching without losing current results
- Tab completes the new command

### Results List
- **Arrow keys** navigate — instant scroll (no animation, Apple-native feel)
- Items **fade in/out** as query filters — no sliding
- Enter opens selected item in detail view
- Tab on a note opens it directly

---

## Natural Language Parsing

- **Dates & times** — "tomorrow", "next Monday", "at 3pm", "in 2 hours"
- **Recurrence** — "every day", "every Monday", "weekly", "monthly"
- **`#tags`** — extracted from text, stored separately
- **`@participants`** — extracted from meeting text
- **Checklist detection** — 2+ comma-separated short items, no time/meeting keywords

---

## Jott Inbox (`/inbox` or `/i`)

- Unified timeline of **all** notes, reminders and meetings
- Sorted by most recent
- Same row UI as individual mode lists
- Arrow keys, Enter to open

---

## Note Linking

- **`[[` autocomplete** — type `[[` to open a picker inline; inserts `[[Note Title]]` wiki-link
- **Link highlighting** — `[[...]]` rendered with purple text + soft purple background + underline
- **Backlinks** — notes track which other notes link to them
- Add link from detail view info popover

---

## Clipboard Monitor

- Watches pasteboard every 0.4s for text changes
- If you copy text and open Jott within 60 seconds, it pre-fills the bar
- Consumed on first use; closing without saving clears it

---

## Voice Capture

- `SFSpeechRecognizer` + `AVAudioEngine` fully implemented
- Live partial transcription results
- Auto-punctuation on macOS 13+
- Audio level (RMS 0–1) exposed for waveform UI
- *(Mic button not yet connected to UI — wired up internally)*

---

## Detail View

### Header
- Back button + compact icon strip: **Pin**, **Edit** (pencil), **Copy**, **Open in editor**, **ⓘ info**, **Trash**

### Content Area
- Note text with `.textSelection(.enabled)`
- **Double-tap anywhere** on text to enter edit mode
- Markdown toggle in top-right corner
- Full inline editor in edit mode

### Info Popover (ⓘ)
- Created date, modified date, word count
- Tags as filter chips
- Linked notes + backlinks
- "Add link" button

### Footer
- "Modified Xm ago · N words"
- Relative time: just now / Xm ago / Xh ago / Xd ago / MMM d

### Navigation Animation
- Capture → Detail: push from trailing
- Detail → Capture: push from leading

---

## Reminders

- NLP parses due date + time
- Recurrence (daily / weekly / monthly / yearly)
- macOS local notifications via `UNUserNotificationCenter`
- **Apple Reminders sync** via EventKit `EKReminder` (if connected)
- Snooze from detail view
- Status badge: pending / done / snoozed

---

## Meetings

- Title, participants (`@name`), start time parsed by NLP
- **Apple Calendar sync** via EventKit `EKEvent` (if connected)
- Selectable target calendar per meeting
- Meeting detail: participants list + time

---

## Settings (Menubar → Settings...)

Opens a dedicated settings window with:

### Calendar
- **Connect Apple Calendar** button (requests permission)
- **Pick which calendar** to use for new events (color-coded list of all writable calendars)
- Connected status indicator

### Reminders
- **Connect Apple Reminders** button (works on macOS 13 + 14+)
- **Pick which list** to use for new reminders (color-coded)
- Connected status indicator

### Google Calendar & Outlook
- Automatic — if added to macOS Calendar app (via CalDAV), calendars appear in the picker above
- **"Google Calendar"** and **"Outlook"** buttons deep-link to System Settings → Internet Accounts
- No manual OAuth needed — macOS handles the sync

### Notes Folder
- Shortcut to change where `.md` note files are stored

---

## Menubar Popover

- **Recent notes** — top 3, title + relative date (time today, "Yesterday", "Mar 27" older)
- **All Notes (N)** — total count, opens `/notes` browse in overlay
- **Dark / Light mode** toggle
- **Choose Notes Folder...**
- **Settings...** — opens settings window
- **Quit**
- Fixed 320pt width — text clamped, no layout expansion
- `NSApp.activate(ignoringOtherApps: true)` on appear — fixes first-click issue

---

## Keyboard Reference

| Key | Action |
|---|---|
| `Option+Space` | Toggle overlay |
| `Escape` | Dismiss overlay |
| `Tab` | Complete command / cycle type (note→reminder→meeting) |
| `↑` / `↓` | Navigate results list |
| `Enter` | Create item / open selected |
| `Shift+Enter` | New line in text |
| Double-click note | Enter edit mode in detail view |
| `Cmd+B / Cmd+I` | Bold / Italic via format bar |

---

## Data & Storage

- **NoteStore** — file-based, notes stored as `.md` in user-chosen folder
- **Notes** — text, tags, created/modified dates, linked note IDs, pinned flag
- **Reminders** — text, due date, recurrence, tags, snooze state
- **Meetings** — title, participants, start time, tags
- **TimelineItem** — unified wrapper for all types in search/inbox views

---

## Not Yet Connected to UI

| Feature | Status |
|---|---|
| Voice capture mic button | Fully implemented (`SpeechManager`), no UI trigger yet |
| `#tag` autocomplete while typing | Model exists, no suggestion bar |
| `/today` daily note | Not implemented |
| Inline math evaluation | Not implemented |
| `/clip` clipboard history picker | Data exists (`ClipboardMonitor`), no command |
