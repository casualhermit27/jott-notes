import Foundation
import Combine
import SwiftUI
import AppKit
import EventKit

enum DetectedType { case note, reminder, meeting }
enum FilterType   { case all, notes, reminders, meetings }

@MainActor
final class OverlayViewModel: ObservableObject {

    // MARK: - Published State
    @Published var inputText: String = "" {
        didSet {
            guard !isProcessing else { return }
            isProcessing = true
            defer { isProcessing = false }
            stripCreationPrefixIfNeeded()   // strip /note , /reminder , /meeting  → sets forcedTypeOverride
            detectType()
            updateCommandSelectionIfNeeded()
            scheduleAutoSave()
        }
    }
    @Published var isVisible: Bool = false
    @Published var detectedType: DetectedType = .note
    @Published var autoSaveStatus: String = ""   // "" | "saved"
    @Published var isDarkMode: Bool = false
    @Published var filterType: FilterType = .all

    // Detail navigation
    @Published var selectedNote: Note?
    @Published var selectedReminder: Reminder?
    @Published var selectedMeeting: Meeting?

    // Note editing
    @Published var isEditingNote: Bool = false
    @Published var editingNoteText: String = ""
    @Published var selectedCommandIndex: Int = 0

    // MARK: - Private
    private let store: NoteStore
    private var isProcessing = false
    private var lastCommand: JottCommand?

    /// Stable ID for the current open session's note
    private var sessionNoteId: UUID?
    private var autoSaveTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    // MARK: - Calendar
    let calendarManager = CalendarManager.shared

    // MARK: - Init
    init(store: NoteStore? = nil) {
        self.store = store ?? NoteStore.shared
        self.isDarkMode = UserDefaults.standard.bool(forKey: "jott_darkMode")
    }

    // MARK: - Forced creation mode (/note , /reminder , /meeting )

    /// Set when user types a creation prefix + space — prefix is then stripped from inputText
    @Published var forcedTypeOverride: DetectedType? = nil

    /// Effective forced type — checks override first, then live prefix (before stripping)
    var forcedType: DetectedType? {
        if let o = forcedTypeOverride { return o }
        let low = inputText.lowercased()
        if low.hasPrefix("/note ")     { return .note }
        if low.hasPrefix("/reminder ") { return .reminder }
        if low.hasPrefix("/meeting ")  { return .meeting }
        return nil
    }

    /// True when in forced creation mode (suppress browse results, show type badge)
    var isForcedCreationMode: Bool { forcedType != nil }

    /// Backspace on empty field — clears the locked type so user can pick another
    func clearForcedType() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            forcedTypeOverride = nil
        }
    }

    /// Called from inputText didSet — strips creation prefix and locks type
    private func stripCreationPrefixIfNeeded() {
        let low = inputText.lowercased()
        let prefixes: [(String, DetectedType)] = [
            ("/note ", .note), ("/reminder ", .reminder), ("/meeting ", .meeting)
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
        } else if low.contains("meeting with") || low.contains("call with")
                   || low.contains("sync with") || low.contains("standup") || low.contains("@") {
            detectedType = .meeting
        } else {
            detectedType = .note
        }
    }

    // MARK: - Session-based auto-save (debounced 0.6s)
    private func scheduleAutoSave() {
        guard commandMode == nil else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowable = !text.hasPrefix("/") || isForcedCreationMode
        guard !text.isEmpty, allowable else { return }

        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            commitSession()
            showSavedIndicator()
        }
    }

    /// Saves (or updates) the single note for this open session
    private func commitSession() {
        let raw = inputText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }

        // Forced type — inputText is already the clean content (prefix was stripped on input)
        if let forced = forcedTypeOverride {
            let text = raw   // prefix already gone
            guard !text.isEmpty else { return }

            let id = sessionNoteId ?? UUID()
            sessionNoteId = id

            switch forced {
            case .note:
                let parsed = NaturalLanguageParser.parse(text)
                if case .note(let t, let tags) = parsed {
                    store.upsertNote(Note(id: id, text: t, tags: tags))
                } else {
                    store.upsertNote(Note(id: id, text: text))
                }
            case .reminder:
                let parsed = NaturalLanguageParser.parse(text)
                if case .reminder(let t, let d, let tags) = parsed {
                    let r = Reminder(text: t, dueDate: d, tags: tags)
                    store.saveReminder(r); NotificationManager.shared.scheduleReminder(r)
                } else {
                    let d = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    let r = Reminder(text: text, dueDate: d, tags: [])
                    store.saveReminder(r); NotificationManager.shared.scheduleReminder(r)
                }
            case .meeting:
                let parsed = NaturalLanguageParser.parse(text)
                if case .meeting(let title, let participants, let startTime, let tags) = parsed {
                    store.saveMeeting(Meeting(title: title, participants: participants, startTime: startTime, tags: tags))
                } else {
                    store.saveMeeting(Meeting(title: text, participants: [], startTime: Date(), tags: []))
                }
            }
            return
        }

        guard !raw.hasPrefix("/") else { return }

        let id = sessionNoteId ?? UUID()
        sessionNoteId = id

        let parsed = NaturalLanguageParser.parse(raw)
        switch parsed {
        case .note(let noteText, let tags):
            store.upsertNote(Note(id: id, text: noteText, tags: tags))
            resolveWikiLinks(noteId: id, text: noteText)

        case .reminder(let reminderText, let dueDate, let tags):
            let reminder = Reminder(text: reminderText, dueDate: dueDate, tags: tags)
            store.saveReminder(reminder)
            NotificationManager.shared.scheduleReminder(reminder)

        case .meeting(let title, let participants, let startTime, let tags):
            store.saveMeeting(Meeting(title: title, participants: participants, startTime: startTime, tags: tags))
        }
    }

    private func showSavedIndicator() {
        statusTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) { autoSaveStatus = "saved" }
        statusTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) { autoSaveStatus = "" }
        }
    }

    // MARK: - Lifecycle
    func show() {
        autoSaveStatus = ""
        if !inputText.isEmpty {
            isVisible = true
            return
        }
        forcedTypeOverride = nil
        sessionNoteId = nil
        selectedNote = nil
        selectedReminder = nil
        selectedMeeting = nil
        isEditingNote = false
        // Clipboard watch: pre-fill if user just copied something
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
        autoSaveTask?.cancel()
        commandMode = nil
        // Save whatever is typed right now (if non-empty)
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && (!text.hasPrefix("/") || isForcedCreationMode) {
            commitSession()
        }
        isVisible = false
        selectedNote = nil
        selectedReminder = nil
        selectedMeeting = nil
        isEditingNote = false
        autoSaveStatus = ""
    }

    func toggle() { isVisible ? dismiss() : show() }
    func handleEscape() { dismiss() }

    var currentCommand: JottCommand? {
        if let mode = commandMode {
            switch mode {
            case .notes:     return .notes(query: inputText)
            case .reminders: return .reminders(query: inputText)
            case .meetings:  return .meetings(query: inputText)
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
        case .meetings(let q):
            let all = getAllMeetings()
            if q.isEmpty { return all.map { .meeting($0) } }
            return all.filter { $0.title.lowercased().contains(q.lowercased()) }.map { .meeting($0) }
        case .search(let q):
            guard !q.isEmpty else { return [] }
            return searchNotes(q).map { .note($0) }
        case .open:
            return []
        case .calendar:
            return []
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
        case .meeting(let m):  selectedMeeting = m
        }
    }

    // MARK: - Tag filter
    @Published var activeTagFilter: String? = nil

    func setTagFilter(_ tag: String?) {
        withAnimation(.easeInOut(duration: 0.2)) { activeTagFilter = tag }
    }

    // MARK: - Data access
    func getAllNotes() -> [Note] {
        let notes = store.allNotes()
        guard let tag = activeTagFilter else { return notes }
        return notes.filter { $0.tags.contains(tag) }
    }
    func getAllReminders() -> [Reminder] { store.allReminders() }
    func getAllMeetings()  -> [Meeting]  { store.allMeetings() }

    func searchNotes(_ query: String) -> [Note] {
        guard !query.isEmpty else { return getAllNotes() }
        let q = query.lowercased()
        return getAllNotes().filter { $0.text.lowercased().contains(q) }
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

    func deleteMeeting(_ id: UUID) {
        store.deleteMeeting(id)
        objectWillChange.send()
    }

    // MARK: - Calendar
    func getUpcomingCalendarEvents() -> [EKEvent] {
        calendarManager.upcomingEvents()
    }

    func importCalendarEvent(_ event: EKEvent) {
        let meeting = calendarManager.importAsMeeting(event)
        store.saveMeeting(meeting)
        objectWillChange.send()
    }

    // MARK: - Dark mode
    func toggleDarkMode() {
        isDarkMode.toggle()
        UserDefaults.standard.set(isDarkMode, forKey: "jott_darkMode")
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

    // MARK: - [[ Inline Link Autocomplete
    @Published var isLinkAutocompleting: Bool = false
    @Published var linkQuery: String = ""
    @Published var linkCandidates: [Note] = []
    @Published var selectedLinkIndex: Int = 0
    /// Set by selectLinkCandidate; consumed by JottNativeInput.updateNSView to do the text replacement.
    @Published var pendingLinkCompletionTitle: String? = nil

    func updateLinkQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let all = store.allNotes()
        linkCandidates = all
            .filter { note in
                guard note.id != sessionNoteId else { return false }
                let title = noteTitleLine(note)
                if trimmed.isEmpty { return true }
                return title.lowercased().contains(trimmed.lowercased())
                    || note.text.lowercased().contains(trimmed.lowercased())
            }
            .prefix(6)
            .map { $0 }
        linkQuery = query
        selectedLinkIndex = 0
        isLinkAutocompleting = true
    }

    func selectLinkCandidate(_ note: Note) {
        pendingLinkCompletionTitle = noteTitleLine(note)
        dismissLinkAutocomplete()
    }

    func selectCurrentLinkCandidate() {
        guard !linkCandidates.isEmpty else { return }
        selectLinkCandidate(linkCandidates[selectedLinkIndex])
    }

    func moveLinkSelection(by delta: Int) {
        guard !linkCandidates.isEmpty else { return }
        selectedLinkIndex = max(0, min(linkCandidates.count - 1, selectedLinkIndex + delta))
    }

    func dismissLinkAutocomplete() {
        isLinkAutocompleting = false
        linkQuery = ""
        linkCandidates = []
        selectedLinkIndex = 0
    }

    private func noteTitleLine(_ note: Note) -> String {
        note.text.components(separatedBy: "\n").first(where: { !$0.isEmpty }) ?? note.text
    }

    /// Called after saving a note — resolves [[title]] syntax into linkedNoteIds.
    private func resolveWikiLinks(noteId: UUID, text: String) {
        guard let expr = try? NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]") else { return }
        let ns = text as NSString
        let matches = expr.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            guard m.numberOfRanges > 1 else { continue }
            let r = m.range(at: 1)
            guard r.location != NSNotFound else { continue }
            let rawTitle = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawTitle.isEmpty else { continue }
            let needle = rawTitle.lowercased()
            let candidates = store.allNotes().filter { $0.id != noteId }

            let exact = candidates.first(where: {
                let t = ($0.text.components(separatedBy: "\n").first(where: { !$0.isEmpty }) ?? $0.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return t == needle
            })
            if let target = exact {
                store.linkNotes(fromId: noteId, toId: target.id)
                continue
            }

            let prefixMatches = candidates.filter {
                let t = ($0.text.components(separatedBy: "\n").first(where: { !$0.isEmpty }) ?? $0.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return t.hasPrefix(needle)
            }
            if prefixMatches.count == 1, let target = prefixMatches.first {
                store.linkNotes(fromId: noteId, toId: target.id)
                continue
            }

            let containsMatches = candidates.filter {
                let t = ($0.text.components(separatedBy: "\n").first(where: { !$0.isEmpty }) ?? $0.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return t.contains(needle)
            }
            if containsMatches.count == 1, let target = containsMatches.first {
                store.linkNotes(fromId: noteId, toId: target.id)
            }
        }
    }

    // MARK: - Note Linking (UI picker)
    @Published var showingLinkPicker: Bool = false

    func linkNote(_ fromId: UUID, to toId: UUID) {
        store.linkNotes(fromId: fromId, toId: toId)
        if selectedNote?.id == fromId {
            selectedNote = store.note(for: fromId)
        }
        objectWillChange.send()
    }

    func unlinkNote(_ fromId: UUID, from toId: UUID) {
        store.unlinkNotes(fromId: fromId, toId: toId)
        if selectedNote?.id == fromId {
            selectedNote = store.note(for: fromId)
        }
        objectWillChange.send()
    }

    func linkedNotes(for note: Note) -> [Note] {
        note.linkedNoteIds.compactMap { store.note(for: $0) }
    }

    func backlinks(for note: Note) -> [Note] {
        store.backlinks(for: note.id)
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

    func cancelEditingNote() {
        isEditingNote = false
        editingNoteText = ""
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

    func activateCommandMode(_ cmd: JottCommand) {
        commandMode = cmd
    }

    func clearCommandMode() {
        commandMode = nil
    }

    // MARK: - Command mode creation

    /// Returns (title, date, hasExplicitDate) when commandMode supports creation and inputText is non-empty.
    func commandCreationPreview() -> (title: String, date: Date, hasDate: Bool)? {
        guard let mode = commandMode else { return nil }
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        switch mode {
        case .calendar, .meetings, .reminders:
            let result = NaturalLanguageParser.parseForEvent(from: text)
            return (title: result.title, date: result.date, hasDate: result.hasExplicitDate)
        default:
            return nil
        }
    }

    @discardableResult
    func createFromCommandMode() -> Bool {
        guard let mode = commandMode else { return false }
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return false }
        let result = NaturalLanguageParser.parseForEvent(from: text)

        switch mode {
        case .calendar:
            let ok = calendarManager.createEvent(title: result.title, startDate: result.date)
            if ok { inputText = ""; commandMode = nil; showSavedIndicator() }
            return ok
        case .meetings:
            store.saveMeeting(Meeting(title: result.title, participants: [], startTime: result.date, tags: []))
            inputText = ""; commandMode = nil; showSavedIndicator()
            objectWillChange.send()
            return true
        case .reminders:
            let r = Reminder(text: result.title, dueDate: result.date, tags: [])
            store.saveReminder(r)
            NotificationManager.shared.scheduleReminder(r)
            inputText = ""; commandMode = nil; showSavedIndicator()
            objectWillChange.send()
            return true
        default:
            return false
        }
    }

    // MARK: - Dynamic panel sizing
    @Published var contentHeight: CGFloat = 72
}
