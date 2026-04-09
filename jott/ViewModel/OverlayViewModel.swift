import Foundation
import Combine
import SwiftUI
import AppKit
import EventKit

enum DetectedType { case note, reminder }
enum FilterType   { case all, notes, reminders }

@MainActor
final class OverlayViewModel: ObservableObject {

    // MARK: - Published State
    @Published var inputText: String = "" {
        didSet {
            guard !isProcessing else { return }
            isProcessing = true
            defer { isProcessing = false }
            stripCreationPrefixIfNeeded()   // strip /note , /reminder  → sets forcedTypeOverride
            detectType()
            updateCommandSelectionIfNeeded()
        }
    }
    @Published var isVisible: Bool = false
    @Published var detectedType: DetectedType = .note
    @Published var autoSaveStatus: String = ""   // "" | contextual message
    @Published var feedbackIcon: String = "checkmark.circle.fill"
    @Published var isDarkMode: Bool = false
    @Published var filterType: FilterType = .all

    // Detail navigation
    @Published var selectedNote: Note?
    @Published var selectedReminder: Reminder?
    @Published var selectedMeeting: Meeting?
    @Published private var meetings: [Meeting] = []

    // Note editing
    @Published var isEditingNote: Bool = false
    @Published var editingNoteText: String = ""
    @Published var selectedCommandIndex: Int = 0

    // Subnote context — when set, new notes are created as subnotes of this note
    @Published var subnoteParentId: UUID? = nil

    // Subnote draft session — persists across panel open/close until user explicitly commits
    var subnoteSessionId: UUID? = nil
    var subnoteSessionParentId: UUID? = nil
    var subnoteSessionText: String = ""

    // MARK: - Private
    private let providedStore: NoteStore?
    private var store: NoteStore { providedStore ?? NoteStore.shared }
    private var isProcessing = false
    private var lastCommand: JottCommand?
    private var storeCancellables = Set<AnyCancellable>()

    /// Stable ID for the current open session's note
    private var sessionNoteId: UUID?
    private var statusTask: Task<Void, Never>?

    /// When the panel was last dismissed with content — used for grace-period restore
    private var lastDismissDate: Date?
    private let gracePeriod: TimeInterval = 5 * 60   // 5 minutes

    // MARK: - Calendar
    let calendarManager = CalendarManager.shared

    // MARK: - Position
    @AppStorage("jott_overlayPosition") var overlayPosition: String = "center"

    /// Panel width adapts: full-width at center, slightly narrower at corners.
    var panelDisplayWidth: CGFloat { overlayPosition == "center" ? 520 : 460 }

    // MARK: - Init
    init(store: NoteStore? = nil) {
        self.providedStore = store
        self.isDarkMode = UserDefaults.standard.bool(forKey: "jott_darkMode")

        self.store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &storeCancellables)
    }

    // MARK: - Forced creation mode (/note , /reminder )

    /// Set when user types a creation prefix + space — prefix is then stripped from inputText
    @Published var forcedTypeOverride: DetectedType? = nil

    /// Effective forced type — checks override first, then live prefix (before stripping)
    var forcedType: DetectedType? {
        if let o = forcedTypeOverride { return o }
        let low = inputText.lowercased()
        if low.hasPrefix("/note ")     { return .note }
        if low.hasPrefix("/reminder ") { return .reminder }
        return nil
    }

    /// True when in forced creation mode (suppress browse results, show type badge)
    var isForcedCreationMode: Bool { forcedType != nil }

    /// Backspace on empty field — clears the locked type so user can pick another
    func clearForcedType() {
        withAnimation(JottMotion.content) {
            forcedTypeOverride = nil
        }
    }

    /// Called from inputText didSet — strips creation prefix and locks type
    private func stripCreationPrefixIfNeeded() {
        let low = inputText.lowercased()
        let prefixes: [(String, DetectedType)] = [
            ("/note ", .note), ("/reminder ", .reminder)
        ]
        for (prefix, type) in prefixes {
            guard low.hasPrefix(prefix) else { continue }
            forcedTypeOverride = type
            // Strip the prefix — this fires didSet again but isProcessing blocks it
            inputText = String(inputText.dropFirst(prefix.count))
            return
        }
    }

    // MARK: - Type detection
    private func detectType() {
        guard forcedTypeOverride == nil else { return }   // type already locked
        guard !inputText.hasPrefix("/") else { return }
        let low = inputText.lowercased()
        if low.contains("remind me") || low.contains("remember to") || low.contains("don't forget") {
            detectedType = .reminder
        } else {
            detectedType = .note
        }
    }

    // MARK: - Session-based auto-save (debounced 0.6s)
    /// Saves (or updates) the single note for this open session
    private func commitSession(showFeedback: Bool = true) {
        let raw = inputText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }

        let timeFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
        }()

        // Forced type — inputText is already the clean content (prefix was stripped on input)
        if let forced = forcedTypeOverride {
            let text = raw   // prefix already gone
            guard !text.isEmpty else { return }

            let id = sessionNoteId ?? UUID()
            sessionNoteId = id

            switch forced {
            case .note:
                // Check for checklist first
                if let items = NaturalLanguageParser.detectChecklist(text) {
                    let mdText = items.map { "- \($0)" }.joined(separator: "\n")
                    store.upsertNote(Note(id: id, text: mdText, parentId: subnoteParentId))
                    if showFeedback {
                        showStoreFeedback(success: "Checklist · \(items.count) items", icon: "checklist")
                    }
                    return
                }
                let parsed = NaturalLanguageParser.parse(text)
                if case .note(let t, let tags) = parsed {
                    store.upsertNote(Note(id: id, text: t, tags: tags, parentId: subnoteParentId))
                } else {
                    store.upsertNote(Note(id: id, text: text, parentId: subnoteParentId))
                }
                if showFeedback {
                    showStoreFeedback(success: "Note saved", icon: "note.text")
                }
            case .reminder:
                let parsed = NaturalLanguageParser.parse(text)
                let rec = NaturalLanguageParser.extractRecurrence(from: text)
                if case .reminder(let t, let d, let tags) = parsed {
                    let r = Reminder(text: t, dueDate: d, tags: tags)
                    store.saveReminder(r); NotificationManager.shared.scheduleReminder(r)
                    let timeStr = timeFmt.string(from: d)
                    if showFeedback, calendarManager.createReminder(title: t, dueDate: d, recurrence: rec) {
                        showStoreFeedback(success: "Reminder → Apple Reminders · \(timeStr)", icon: "bell.fill")
                    } else if showFeedback {
                        showStoreFeedback(success: "Reminder set · \(timeStr)", icon: "bell.fill")
                    } else {
                        _ = calendarManager.createReminder(title: t, dueDate: d, recurrence: rec)
                    }
                } else {
                    let d = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    let r = Reminder(text: text, dueDate: d, tags: [])
                    store.saveReminder(r); NotificationManager.shared.scheduleReminder(r)
                    let timeStr = timeFmt.string(from: d)
                    if showFeedback, calendarManager.createReminder(title: text, dueDate: d, recurrence: rec) {
                        showStoreFeedback(success: "Reminder → Apple Reminders · \(timeStr)", icon: "bell.fill")
                    } else if showFeedback {
                        showStoreFeedback(success: "Reminder set · \(timeStr)", icon: "bell.fill")
                    } else {
                        _ = calendarManager.createReminder(title: text, dueDate: d, recurrence: rec)
                    }
                }
            }
            return
        }

        guard !raw.hasPrefix("/") else { return }

        // Check for checklist before NLP parse
        if let items = NaturalLanguageParser.detectChecklist(raw) {
            let id = sessionNoteId ?? UUID()
            sessionNoteId = id
            let mdText = items.map { "- \($0)" }.joined(separator: "\n")
            store.upsertNote(Note(id: id, text: mdText, parentId: subnoteParentId))
            if showFeedback {
                showStoreFeedback(success: "Checklist · \(items.count) items", icon: "checklist")
            }
            return
        }

        let id = sessionNoteId ?? UUID()
        sessionNoteId = id

        let parsed = NaturalLanguageParser.parse(raw)
        switch parsed {
        case .note(let noteText, let tags):
            store.upsertNote(Note(id: id, text: noteText, tags: tags, parentId: subnoteParentId))
            if showFeedback {
                showStoreFeedback(success: "Note saved", icon: "note.text")
            }

        case .reminder(let reminderText, let dueDate, let tags):
            let reminder = Reminder(text: reminderText, dueDate: dueDate, tags: tags)
            store.saveReminder(reminder)
            NotificationManager.shared.scheduleReminder(reminder)
            let rec = NaturalLanguageParser.extractRecurrence(from: raw)
            let timeStr = timeFmt.string(from: dueDate)
            if showFeedback, calendarManager.createReminder(title: reminderText, dueDate: dueDate, recurrence: rec) {
                showStoreFeedback(success: "Reminder → Apple Reminders · \(timeStr)", icon: "bell.fill")
            } else if showFeedback {
                showStoreFeedback(success: "Reminder set · \(timeStr)", icon: "bell.fill")
            } else {
                _ = calendarManager.createReminder(title: reminderText, dueDate: dueDate, recurrence: rec)
            }
        }
    }

    func persistCurrentNoteDraftImmediately() {
        let raw = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard forcedTypeOverride != .reminder else { return }
        guard !raw.hasPrefix("/") || isForcedCreationMode else { return }
        commitSession(showFeedback: false)
        objectWillChange.send()
    }

    func showFeedback(_ message: String, icon: String = "checkmark.circle.fill") {
        statusTask?.cancel()
        feedbackIcon = icon
        withAnimation(JottMotion.content) { autoSaveStatus = message }
        statusTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(JottMotion.content) { autoSaveStatus = "" }
        }
    }

    private func showStoreFeedback(success: String, icon: String) {
        if let error = store.consumeLastErrorMessage() {
            showFeedback(error, icon: "exclamationmark.triangle.fill")
        } else {
            showFeedback(success, icon: icon)
        }
    }

    // MARK: - Lifecycle
    func show() {
        store.refreshFromDisk()
        commandMode = nil

        // Grace-period restore: if dismissed recently with content, bring it back
        if let dismissed = lastDismissDate,
           Date().timeIntervalSince(dismissed) < gracePeriod,
           !inputText.isEmpty {
            // Still within grace period — show saved confirmation then let user continue
            showFeedback("Note saved", icon: "note.text")
            isVisible = true
            return
        }

        // Grace period expired or no prior session — fresh start
        lastDismissDate = nil
        sessionNoteId = nil
        forcedTypeOverride = nil
        selectedNote = nil
        selectedReminder = nil
        isEditingNote = false
        autoSaveStatus = ""

        if let copied = ClipboardMonitor.shared.consume() {
            inputText = copied
            clipboardPrefilled = true
        } else {
            inputText = ""
            clipboardPrefilled = false
        }
        isVisible = true
    }

    func dismiss() {
        // Save before we close
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && text != "?" && (!text.hasPrefix("/") || isForcedCreationMode) {
            commitSession()
            lastDismissDate = Date()
        } else {
            lastDismissDate = nil
            sessionNoteId = nil
        }

        // Start the window dismiss immediately, then reset all UI state
        // without animations so the dropdown/toolbar never visibly collapse
        // — the window exit animation is the only thing the user sees.
        isVisible = false
        withTransaction(Transaction(animation: nil)) {
            commandMode = nil
            commandModeDateOverride = nil
            inputText = ""
            selectedNote = nil
            selectedReminder = nil
            isEditingNote = false
            autoSaveStatus = ""
            subnoteParentId = nil
        }
    }

    func toggle() { isVisible ? dismiss() : show() }

    func handleEscape() {
        if selectedNote != nil || selectedReminder != nil {
            if let note = selectedNote, isEditingNote { saveEditedNote(note) }
            selectedNote = nil
            selectedReminder = nil
            isEditingNote = false
        } else {
            dismiss()
        }
    }

    /// True when user is in a command mode but has started typing "/" to switch to another command
    var isTypingNewCommand: Bool {
        commandMode != nil && inputText.hasPrefix("/") && !isForcedCreationMode
    }

    var currentCommand: JottCommand? {
        if let mode = commandMode {
            // If typing a new "/" command, show current mode results with empty query
            // (so the list stays useful while the suggestion bar offers the switch)
            if isTypingNewCommand {
                switch mode {
                case .notes:     return .notes(query: "")
                case .reminders: return .reminders(query: "")
                case .inbox:     return .inbox
                case .today:     return .today
                default:         return mode
                }
            }
            switch mode {
            case .notes:     return .notes(query: inputText)
            case .reminders: return .reminders(query: inputText)
            case .search:    return .search(query: inputText)
            default:         return mode
            }
        }
        if isForcedCreationMode { return nil }
        return JottCommand(input: inputText)
    }

    func currentCommandItems() -> [TimelineItem] {
        guard let cmd = currentCommand else { return [] }
        return commandItems(for: cmd)
    }

    func commandItems(for command: JottCommand) -> [TimelineItem] {
        switch command {
        case .notes(let q):
            let notes = q.isEmpty ? getAllNotes() : searchNotes(q)
            return notes.map { .note($0) }
        case .reminders(let q):
            let all = getAllReminders()
            if q.isEmpty { return all.map { .reminder($0) } }
            return all.filter { $0.text.lowercased().contains(q.lowercased()) }.map { .reminder($0) }
        case .search(let q):
            let notes = searchNotes(q).map { TimelineItem.note($0) }
            let reminders: [TimelineItem]
            if q.isEmpty {
                reminders = getAllReminders().map { TimelineItem.reminder($0) }
            } else {
                reminders = getAllReminders()
                    .filter { $0.text.lowercased().contains(q.lowercased()) }
                    .map { TimelineItem.reminder($0) }
            }
            return (notes + reminders).sorted { $0.date > $1.date }
        case .open:
            return []
        case .calendar:
            return []
        case .inbox:
            let notes = getAllNotes().map { TimelineItem.note($0) }
            let reminders = getAllReminders().map { TimelineItem.reminder($0) }
            return (notes + reminders).sorted { $0.date > $1.date }
        case .today:
            let cal = Calendar.current
            return getAllReminders()
                .filter { !$0.isCompleted && cal.isDateInToday($0.dueDate) }
                .sorted { $0.dueDate < $1.dueDate }
                .map { TimelineItem.reminder($0) }
        }
    }

    func updateCommandSelectionIfNeeded() {
        let cmd = currentCommand
        if cmd != lastCommand {
            selectedCommandIndex = 0
            lastCommand = cmd
        }
        if cmd == nil {
            selectedCommandIndex = 0
        }
    }

    func moveCommandSelection(by delta: Int) {
        let items = currentCommandItems()
        guard !items.isEmpty else { return }
        let next = max(0, min(selectedCommandIndex + delta, items.count - 1))
        selectedCommandIndex = next
    }

    func openSelectedCommandItem() {
        let items = currentCommandItems()
        guard !items.isEmpty else { return }
        let idx = max(0, min(selectedCommandIndex, items.count - 1))
        switch items[idx] {
        case .note(let n):     selectedNote = n
        case .reminder(let r): selectedReminder = r
        }
    }

    // MARK: - Tag filter
    @Published var activeTagFilter: String? = nil

    func setTagFilter(_ tag: String?) {
        withAnimation(JottMotion.content) { activeTagFilter = tag }
    }

    // MARK: - Data access
    /// Root notes only — used for browsing (inbox, notes list, smart recall).
    func getAllNotes() -> [Note] {
        let notes = store.allNotes().filter { $0.parentId == nil }
        guard let tag = activeTagFilter else { return notes }
        return notes.filter { $0.tags.contains(tag) }
    }

    func getAllReminders() -> [Reminder] { store.allReminders() }
    func getAllMeetings() -> [Meeting] { meetings.sorted { $0.startTime < $1.startTime } }

    /// Search includes subnotes, showing them with a parent breadcrumb via the existing UI.
    func searchNotes(_ query: String) -> [Note] {
        guard !query.isEmpty else { return getAllNotes() }
        let q = query.lowercased()
        return store.allNotes().filter { $0.text.lowercased().contains(q) }
    }

    // MARK: - Pin
    func togglePin(_ note: Note) {
        store.togglePin(note.id)
        if selectedNote?.id == note.id { selectedNote = store.note(for: note.id) }
        objectWillChange.send()
    }

    // MARK: - Delete
    func deleteNote(_ id: UUID) {
        store.deleteNote(id)
        objectWillChange.send()
    }

    func deleteReminder(_ id: UUID) {
        NotificationManager.shared.cancelReminder(id)
        store.deleteReminder(id)
        objectWillChange.send()
    }

    // MARK: - Calendar
    func getUpcomingCalendarEvents() -> [EKEvent] {
        calendarManager.upcomingEvents()
    }

    func importCalendarEvent(_ event: EKEvent) {
        let participants = (event.attendees ?? [])
            .compactMap { attendee -> String? in
                if let name = attendee.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    return name
                }
                return attendee.url.absoluteString
            }

        let trimmedTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if let trimmedTitle, !trimmedTitle.isEmpty {
            title = trimmedTitle
        } else {
            title = "Untitled"
        }
        let start = event.startDate ?? Date()
        let durationMinutes = max(1, Int((event.endDate ?? start).timeIntervalSince(start) / 60))

        var meeting = Meeting(
            title: title,
            participants: participants,
            startTime: start,
            duration: durationMinutes,
            tags: []
        )
        meeting.description = event.notes

        if !meetings.contains(where: { $0.title == meeting.title && $0.startTime == meeting.startTime }) {
            meetings.append(meeting)
        }
        let selectedTitle = meeting.title
        let selectedStartTime = meeting.startTime
        let matchedMeeting = meetings.first { existingMeeting in
            existingMeeting.title == selectedTitle && existingMeeting.startTime == selectedStartTime
        }
        selectedMeeting = matchedMeeting ?? meeting
        objectWillChange.send()
    }

    // MARK: - Dark mode
    func toggleDarkMode() {
        isDarkMode.toggle()
        UserDefaults.standard.set(isDarkMode, forKey: "jott_darkMode")
    }

    func setDarkMode(_ enabled: Bool) {
        isDarkMode = enabled
        UserDefaults.standard.set(enabled, forKey: "jott_darkMode")
    }

    // MARK: - Clipboard
    @Published var clipboardPrefilled: Bool = false

    func clearClipboardPrefill() {
        inputText = ""
        clipboardPrefilled = false
    }

    // MARK: - Snooze
    func snoozeReminder(_ reminder: Reminder, minutes: Int) {
        let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
        store.snoozeReminder(reminder.id, until: date)
        NotificationManager.shared.snoozeReminder(reminder, until: date)
        if selectedReminder?.id == reminder.id {
            var updated = reminder
            updated.dueDate = date
            selectedReminder = updated
        }
        objectWillChange.send()
    }

    func snoozeReminderToTomorrow(_ reminder: Reminder) {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.day! += 1
        comps.hour = 9
        comps.minute = 0
        let date = Calendar.current.date(from: comps) ?? Date().addingTimeInterval(86400)
        store.snoozeReminder(reminder.id, until: date)
        NotificationManager.shared.snoozeReminder(reminder, until: date)
        if selectedReminder?.id == reminder.id {
            var updated = reminder
            updated.dueDate = date
            selectedReminder = updated
        }
        objectWillChange.send()
    }


    // MARK: - Note editing
    func startEditingNote(_ note: Note) {
        editingNoteText = note.text
        isEditingNote = true
    }

    func saveEditedNote(_ originalNote: Note) {
        let text = editingNoteText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { cancelEditingNote(); return }
        var updated = originalNote
        updated.text = text
        updated.modifiedAt = Date()
        store.upsertNote(updated)
        selectedNote = updated
        cancelEditingNote()
    }

    /// Saves the current edit without exiting edit mode (autosave path).
    func autoSaveEditedNote(_ originalNote: Note) {
        let text = editingNoteText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        var updated = originalNote
        updated.text = text
        updated.modifiedAt = Date()
        store.upsertNote(updated)
        selectedNote = updated
        showFeedback("Saved", icon: "checkmark.circle.fill")
    }

    @discardableResult
    func updateNote(_ originalNote: Note, text: String) -> Note? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var updated = originalNote
        updated.text = trimmed
        updated.modifiedAt = Date()
        store.upsertNote(updated)
        objectWillChange.send()
        return updated
    }

    func cancelEditingNote() {
        isEditingNote = false
        editingNoteText = ""
    }

    // MARK: - Subnotes

    func createSubnote(parentId: UUID, text: String) {
        let note = Note(text: text, parentId: parentId)
        store.upsertNote(note)
        objectWillChange.send()
    }

    /// Auto-saves subnote draft as user types. Reuses same UUID until commitSubnoteDraft() clears it.
    func autoSaveSubnoteDraft(parentId: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Start a new session if parent changed or no session exists
        if subnoteSessionParentId != parentId {
            subnoteSessionId = nil
        }
        subnoteSessionParentId = parentId
        subnoteSessionText = text
        let id = subnoteSessionId ?? UUID()
        subnoteSessionId = id
        store.upsertNote(Note(id: id, text: trimmed, parentId: parentId))
        objectWillChange.send()
    }

    /// Call on Enter — seals the current draft and clears session so next entry is a new subnote.
    func commitSubnoteDraft() {
        subnoteSessionId = nil
        subnoteSessionText = ""
        // Keep subnoteSessionParentId so we know which parent we were on
    }

    /// Discards an unsaved empty draft and clears session.
    func discardSubnoteDraft(parentId: UUID) {
        if subnoteSessionParentId == parentId, let id = subnoteSessionId {
            let text = subnoteSessionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { store.deleteNote(id) }
        }
        subnoteSessionId = nil
        subnoteSessionText = ""
        subnoteSessionParentId = nil
        objectWillChange.send()
    }

    func subnotes(of parentId: UUID) -> [Note] {
        store.subnotes(of: parentId)
    }

    func subnoteCount(of parentId: UUID) -> Int {
        store.subnoteCount(of: parentId)
    }

    func deleteSubnote(_ id: UUID) {
        // Also delete any children of this subnote
        let children = store.subnotes(of: id)
        for child in children { store.deleteNote(child.id) }
        store.deleteNote(id)
        objectWillChange.send()
    }

    func setFilterType(_ type: FilterType) { filterType = type }

    // MARK: - Open / Folder

    func openNoteInEditor(_ note: Note) { store.openNoteInEditor(note) }
    func openNotesFolder()              { store.openNotesFolder() }
    func selectNotesFolder()            { store.selectNotesFolder() }

    // MARK: - Legacy stubs (kept for DetailView compatibility)
    @Published var showFilterMenu: Bool = false

    // MARK: - Command Mode (badge-locked command entry)
    @Published var commandMode: JottCommand? = nil
    /// Overrides the NLP-parsed date when user picks from the date selector.
    @Published var commandModeDateOverride: Date? = nil

    func activateCommandMode(_ cmd: JottCommand) {
        commandMode = cmd
        commandModeDateOverride = nil
    }

    func clearCommandMode() {
        commandMode = nil
        commandModeDateOverride = nil
    }

    // MARK: - Command mode creation

    /// Returns preview info when commandMode supports creation and inputText is non-empty.
    func commandCreationPreview() -> (title: String, date: Date, hasDate: Bool, recurrence: ParsedRecurrence?)? {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        // Resolve which mode to preview for
        let isDateMode: Bool
        if let mode = commandMode {
            switch mode {
            case .calendar, .reminders: isDateMode = true
            default: return nil
            }
        } else if let forced = forcedType {
            switch forced {
            case .reminder: isDateMode = true
            default: return nil
            }
        } else {
            return nil
        }

        guard isDateMode else { return nil }
        let result  = NaturalLanguageParser.parseForEvent(from: text)
        let rec     = NaturalLanguageParser.extractRecurrence(from: text)
        let date    = commandModeDateOverride ?? result.date
        let hasDate = commandModeDateOverride != nil || result.hasExplicitDate
        return (title: result.title, date: date, hasDate: hasDate, recurrence: rec)
    }

    @discardableResult
    func createFromCommandMode() -> Bool {
        guard let mode = commandMode else { return false }
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return false }
        let result = NaturalLanguageParser.parseForEvent(from: text)
        let rec    = NaturalLanguageParser.extractRecurrence(from: text)
        let date   = commandModeDateOverride ?? result.date

        let timeFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
        }()
        let timeStr = timeFmt.string(from: date)

        switch mode {
        case .calendar:
            let ok = calendarManager.createEvent(title: result.title, startDate: date, recurrence: rec)
            if ok {
                inputText = ""; commandMode = nil
                showFeedback("Event → Apple Calendar · \(timeStr)", icon: "calendar")
            }
            return ok
        case .reminders:
            let r = Reminder(text: result.title, dueDate: date, tags: [])
            store.saveReminder(r)
            NotificationManager.shared.scheduleReminder(r)
            inputText = ""; commandMode = nil
            if calendarManager.createReminder(title: result.title, dueDate: date, recurrence: rec) {
                showStoreFeedback(success: "Reminder → Apple Reminders · \(timeStr)", icon: "bell.fill")
            } else {
                showStoreFeedback(success: "Reminder set · \(timeStr)", icon: "bell.fill")
            }
            objectWillChange.send()
            return true
        default:
            return false
        }
    }

    /// Unified creation — works for both commandMode and forcedType (Enter key handler).
    /// Saves, shows feedback, clears input for next entry — does NOT dismiss.
    func createCurrentItem() {
        if commandMode != nil {
            createFromCommandMode()
            return
        }
        guard let forced = forcedTypeOverride else { return }
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let timeFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
        }()

        switch forced {
        case .reminder:
            let result = NaturalLanguageParser.parseForEvent(from: text)
            let rec    = NaturalLanguageParser.extractRecurrence(from: text)
            let date   = commandModeDateOverride ?? result.date
            let r = Reminder(text: result.title, dueDate: date, tags: [])
            store.saveReminder(r)
            NotificationManager.shared.scheduleReminder(r)
            if calendarManager.createReminder(title: result.title, dueDate: date, recurrence: rec) {
                showStoreFeedback(success: "Reminder → Apple Reminders · \(timeFmt.string(from: date))", icon: "bell.fill")
            } else {
                showStoreFeedback(success: "Reminder set · \(timeFmt.string(from: date))", icon: "bell.fill")
            }
        case .note:
            commitSession(showFeedback: false)
            showStoreFeedback(success: "Note saved", icon: "note.text")
        }

        // Reset for next entry — stay open
        sessionNoteId = nil
        commandModeDateOverride = nil
        subnoteParentId = nil
        inputText = ""
        objectWillChange.send()
    }

    // MARK: - Smart Recall
    var smartRecallResults: [TimelineItem] {
        guard commandMode == nil,
              !isForcedCreationMode,
              !inputText.hasPrefix("/"),
              inputText.count >= 2 else { return [] }
        let q = inputText.lowercased()
        var results: [TimelineItem] = []
        // Search all notes (including subnotes) — root notes first, then subnotes
        let all = store.allNotes().filter { $0.text.lowercased().contains(q) }
        let rootMatches = all.filter { $0.parentId == nil }
        let subMatches  = all.filter { $0.parentId != nil }
        let matchingReminders = getAllReminders().filter { $0.text.lowercased().contains(q) }
        results += rootMatches.prefix(2).map { .note($0) }
        results += subMatches.prefix(2).map { .note($0) }
        results += matchingReminders.prefix(2).map { .reminder($0) }
        return Array(results.prefix(5))
    }

    var isSmartRecalling: Bool { !smartRecallResults.isEmpty }

    // MARK: - Tag Autocomplete
    /// Returns the partial tag being typed (text after the last `#` in the last word), or nil if not applicable.
    var tagQuery: String? {
        guard !inputText.hasPrefix("/"), !inputText.isEmpty else { return nil }
        let components = inputText.components(separatedBy: " ")
        guard let last = components.last, last.hasPrefix("#") else { return nil }
        return String(last.dropFirst())
    }

    var isTagAutocompleting: Bool {
        guard let q = tagQuery else { return false }
        return !tagCandidates(for: q).isEmpty
    }

    func tagCandidates(for query: String) -> [String] {
        let allTags = Array(Set(getAllNotes().flatMap { $0.tags })).sorted()
        if query.isEmpty { return Array(allTags.prefix(8)) }
        return Array(allTags.filter { $0.lowercased().hasPrefix(query.lowercased()) }.prefix(8))
    }

    func completeTag(_ tag: String) {
        let suffix = "#\(tagQuery ?? "")"
        guard inputText.hasSuffix(suffix) else { return }
        inputText = String(inputText.dropLast(suffix.count)) + "#\(tag) "
    }

    // MARK: - Quick Complete
    func markReminderDone(_ id: UUID) {
        store.toggleReminder(id)
        objectWillChange.send()
    }

    // MARK: - Inline Editing
    @Published var inlineEditingId: UUID? = nil
    @Published var inlineEditText: String = ""

    func startInlineEdit() {
        let items = currentCommandItems().isEmpty ? smartRecallResults : currentCommandItems()
        guard !items.isEmpty else { return }
        let idx = max(0, min(selectedCommandIndex, items.count - 1))
        switch items[idx] {
        case .note(let n):
            inlineEditingId = n.id
            inlineEditText = n.text.components(separatedBy: "\n").first ?? n.text
        default:
            break // only notes support inline edit for now
        }
    }

    func saveInlineEdit() {
        guard let id = inlineEditingId else { return }
        let newText = inlineEditText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty else { cancelInlineEdit(); return }
        if var note = store.note(for: id) {
            // Replace just the first line
            let lines = note.text.components(separatedBy: "\n")
            if lines.count > 1 {
                note.text = ([newText] + lines.dropFirst()).joined(separator: "\n")
            } else {
                note.text = newText
            }
            note.modifiedAt = Date()
            store.upsertNote(note)
        }
        inlineEditingId = nil
        inlineEditText = ""
        objectWillChange.send()
    }

    func cancelInlineEdit() {
        inlineEditingId = nil
        inlineEditText = ""
    }

    // MARK: - Dynamic panel sizing
    @Published var contentHeight: CGFloat = 72
}
