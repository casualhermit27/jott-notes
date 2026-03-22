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

    // MARK: - Private
    private let store: NoteStore
    private var isProcessing = false

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
        forcedTypeOverride = nil
        sessionNoteId = nil
        inputText = ""
        selectedNote = nil
        selectedReminder = nil
        selectedMeeting = nil
        isEditingNote = false
        autoSaveStatus = ""
        isVisible = true
    }

    func dismiss() {
        autoSaveTask?.cancel()
        // Save whatever is typed right now (if non-empty)
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && (!text.hasPrefix("/") || isForcedCreationMode) {
            commitSession()
        }
        isVisible = false
        inputText = ""
        forcedTypeOverride = nil
        sessionNoteId = nil
        selectedNote = nil
        selectedReminder = nil
        selectedMeeting = nil
        isEditingNote = false
        autoSaveStatus = ""
    }

    func toggle() { isVisible ? dismiss() : show() }
    func handleEscape() { dismiss() }

    // MARK: - Data access
    func getAllNotes()     -> [Note]     { store.allNotes() }
    func getAllReminders() -> [Reminder] { store.allReminders() }
    func getAllMeetings()  -> [Meeting]  { store.allMeetings() }

    func searchNotes(_ query: String) -> [Note] {
        guard !query.isEmpty else { return store.allNotes() }
        let q = query.lowercased()
        return store.allNotes().filter { $0.text.lowercased().contains(q) }
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

    // MARK: - Dynamic panel sizing
    @Published var contentHeight: CGFloat = 72
}
