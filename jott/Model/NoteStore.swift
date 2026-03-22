import Foundation
import AppKit

@MainActor
final class NoteStore {
    static let shared = NoteStore()

    private var notesCache:  [Note] = []
    private var reminders:   [Reminder] = []
    private var meetings:    [Meeting] = []

    private let appSupportDir:    URL
    private let remindersFileURL: URL
    private let meetingsFileURL:  URL

    private let bookmarkKey = "jott_notesFolderBookmark"
    private var securityScopedActive = false

    /// UUID → slug filename mapping (e.g. UUID → "buy-milk.md")
    private var noteFilenames: [UUID: String] = [:]

    /// Folder where .md note files live. Falls back to <AppSupport>/Notes.
    private(set) var notesFolder: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        appSupportDir = appSupport.appending(component: "com.casualhermit.jott",
                                             directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: appSupportDir,
                                                 withIntermediateDirectories: true)

        remindersFileURL = appSupportDir.appending(component: "reminders.json")
        meetingsFileURL  = appSupportDir.appending(component: "meetings.json")

        // Resolve user-selected folder from security-scoped bookmark, or use default
        let defaultFolder = appSupportDir.appending(component: "jott-notes",
                                                    directoryHint: .isDirectory)
        if let bookmarkData = UserDefaults.standard.data(forKey: "jott_notesFolderBookmark") {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                notesFolder = url
                // Refresh stale bookmark
                if stale, let fresh = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(fresh, forKey: "jott_notesFolderBookmark")
                }
                if url.startAccessingSecurityScopedResource() {
                    // keep access open for the app's lifetime
                    _ = true  // suppress warning
                }
            } else {
                notesFolder = defaultFolder
            }
        } else {
            notesFolder = defaultFolder
        }

        try? FileManager.default.createDirectory(at: notesFolder,
                                                 withIntermediateDirectories: true)
        load()
        migrateFromJSON()
    }

    // MARK: - Folder Selection

    func selectNotesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Notes Folder"
        panel.prompt = "Choose"
        panel.message = "Jott will save your notes as Markdown files in this folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Save security-scoped bookmark
        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }

        // Start accessing the new folder
        _ = url.startAccessingSecurityScopedResource()
        notesFolder = url
        try? FileManager.default.createDirectory(at: notesFolder,
                                                 withIntermediateDirectories: true)
        // Re-persist all cached notes into new folder
        for note in notesCache { writeNoteMD(note) }
    }

    // MARK: - Slug helpers

    private func slugify(_ text: String) -> String {
        let lower = text.lowercased()
        // Replace non-alphanumeric characters with hyphens
        var slug = lower.unicodeScalars.map { scalar -> Character in
            let c = Character(scalar)
            if c.isLetter || c.isNumber { return c }
            return "-"
        }
        // Collapse consecutive hyphens
        var result = ""
        var prevWasHyphen = false
        for ch in slug {
            if ch == "-" {
                if !prevWasHyphen && !result.isEmpty { result.append(ch) }
                prevWasHyphen = true
            } else {
                result.append(ch)
                prevWasHyphen = false
            }
        }
        // Trim trailing hyphen
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        // Max 50 chars
        if result.count > 50 {
            result = String(result.prefix(50)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return result
    }

    private func generateFilename(for note: Note) -> String {
        let firstLine = note.text.components(separatedBy: "\n").first ?? note.text
        let slug = slugify(firstLine)
        let base = slug.isEmpty ? "note-\(note.id.uuidString.prefix(4).lowercased())" : slug

        // Check for collisions
        let existing = Set(noteFilenames.values)
        var candidate = "\(base).md"
        if !existing.contains(candidate) { return candidate }
        var counter = 2
        while existing.contains(candidate) {
            candidate = "\(base)-\(counter).md"
            counter += 1
        }
        return candidate
    }

    private func fileURL(for note: Note) -> URL {
        if let filename = noteFilenames[note.id] {
            return notesFolder.appending(component: filename)
        }
        // Generate new slug filename and remember it
        let filename = generateFilename(for: note)
        noteFilenames[note.id] = filename
        return notesFolder.appending(component: filename)
    }

    // MARK: - MD helpers

    private func attachmentsDir() -> URL {
        notesFolder.appending(component: "attachments", directoryHint: .isDirectory)
    }

    private func writeNoteMD(_ note: Note) {
        let iso = ISO8601DateFormatter()
        let fm = """
        ---
        id: \(note.id.uuidString)
        tags: \(note.tags.joined(separator: ", "))
        created: \(iso.string(from: note.timestamp))
        modified: \(iso.string(from: note.modifiedAt))
        ---

        """
        let content = fm + note.text
        try? content.write(to: fileURL(for: note), atomically: true, encoding: .utf8)
    }

    private func readNoteMD(at url: URL) -> Note? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let iso = ISO8601DateFormatter()

        guard content.hasPrefix("---\n") else {
            // Plain text (no frontmatter) — use filename as fallback
            let filenameWithoutExt = url.deletingPathExtension().lastPathComponent
            let uuidFromFilename = UUID(uuidString: filenameWithoutExt)
            let id = uuidFromFilename ?? UUID()
            let note = Note(id: id, text: content.trimmingCharacters(in: .whitespacesAndNewlines),
                        fileURL: url)
            noteFilenames[id] = url.lastPathComponent
            return note
        }

        let parts = content.components(separatedBy: "\n---\n")
        guard parts.count >= 2 else { return nil }
        let frontmatter = String(parts[0].dropFirst(4))  // drop leading "---\n"
        let body = parts.dropFirst().joined(separator: "\n---\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var idStr: String?; var tagsStr = ""; var createdStr: String?; var modStr: String?
        for line in frontmatter.components(separatedBy: "\n") {
            let kv = line.split(separator: ":", maxSplits: 1)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "id":       idStr      = kv[1]
            case "tags":     tagsStr    = kv[1]
            case "created":  createdStr = kv[1]
            case "modified": modStr     = kv[1]
            default: break
            }
        }

        guard let idStr, let id = UUID(uuidString: idStr) else { return nil }
        let tags    = tagsStr.isEmpty ? [] : tagsStr.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let created  = createdStr.flatMap  { iso.date(from: $0) } ?? Date()
        let modified = modStr.flatMap      { iso.date(from: $0) } ?? created

        // Register the filename for this UUID
        noteFilenames[id] = url.lastPathComponent

        return Note(id: id, text: body, tags: tags,
                    timestamp: created, modifiedAt: modified, fileURL: url)
    }

    private func loadNotes() {
        noteFilenames = [:]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: notesFolder,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }
        notesCache = urls
            .filter { $0.pathExtension == "md" }
            .compactMap { readNoteMD(at: $0) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func load() {
        loadNotes()
        if let data = try? Data(contentsOf: remindersFileURL) {
            reminders = (try? JSONDecoder().decode([Reminder].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: meetingsFileURL) {
            meetings = (try? JSONDecoder().decode([Meeting].self, from: data)) ?? []
        }
    }

    /// One-time migration: move notes.json entries to individual .md files
    private func migrateFromJSON() {
        let oldJSON = appSupportDir.appending(component: "notes.json")
        guard FileManager.default.fileExists(atPath: oldJSON.path),
              let data = try? Data(contentsOf: oldJSON),
              let oldNotes = try? JSONDecoder().decode([Note].self, from: data)
        else { return }

        for note in oldNotes {
            let url = fileURL(for: note)
            if !FileManager.default.fileExists(atPath: url.path) {
                writeNoteMD(note)
            }
        }
        try? FileManager.default.removeItem(at: oldJSON)
        loadNotes()
    }

    // MARK: - Notes API

    func upsertNote(_ note: Note) {
        writeNoteMD(note)
        if let idx = notesCache.firstIndex(where: { $0.id == note.id }) {
            notesCache[idx] = note
        } else {
            notesCache.insert(note, at: 0)
        }
    }

    func allNotes() -> [Note] {
        notesCache.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func searchNotes(query: String) -> [Note] {
        let q = query.lowercased()
        return notesCache.filter { note in
            note.text.lowercased().contains(q) ||
            note.tags.contains { $0.lowercased().contains(q) }
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func deleteNote(_ id: UUID) {
        if let filename = noteFilenames[id] {
            let url = notesFolder.appending(component: filename)
            try? FileManager.default.removeItem(at: url)
        }
        noteFilenames.removeValue(forKey: id)
        notesCache.removeAll { $0.id == id }
    }

    func deleteNoteIfEmpty(_ id: UUID) {
        if let note = notesCache.first(where: { $0.id == id }),
           note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deleteNote(id)
        }
    }

    func openNoteInEditor(_ note: Note) {
        let url = note.fileURL ?? fileURL(for: note)
        NSWorkspace.shared.open(url)
    }

    func openNotesFolder() {
        NSWorkspace.shared.open(notesFolder)
    }

    // MARK: - Attachments

    func saveAttachment(data: Data, filename: String) -> String? {
        let dir = attachmentsDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appending(component: filename)
        do {
            try data.write(to: dest, options: .atomic)
            return "attachments/\(filename)"
        } catch {
            return nil
        }
    }

    // MARK: - Reminders

    func saveReminder(_ reminder: Reminder) {
        reminders.insert(reminder, at: 0)
        persistReminders()
    }

    func allReminders() -> [Reminder] {
        reminders.sorted { $0.dueDate < $1.dueDate }
    }

    func upcomingReminders() -> [Reminder] {
        let now = Date()
        return reminders.filter { !$0.isCompleted && $0.dueDate > now }
            .sorted { $0.dueDate < $1.dueDate }
    }

    func toggleReminder(_ id: UUID) {
        if let idx = reminders.firstIndex(where: { $0.id == id }) {
            reminders[idx].isCompleted.toggle()
            persistReminders()
        }
    }

    func deleteReminder(_ id: UUID) {
        reminders.removeAll { $0.id == id }
        persistReminders()
    }

    private func persistReminders() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        try? data.write(to: remindersFileURL, options: .atomic)
    }

    // MARK: - Meetings

    func saveMeeting(_ meeting: Meeting) {
        meetings.insert(meeting, at: 0)
        persistMeetings()
    }

    func allMeetings() -> [Meeting] {
        meetings.sorted { $0.startTime < $1.startTime }
    }

    func upcomingMeetings() -> [Meeting] {
        let now = Date()
        return meetings.filter { $0.startTime > now }
            .sorted { $0.startTime < $1.startTime }
    }

    func deleteMeeting(_ id: UUID) {
        meetings.removeAll { $0.id == id }
        persistMeetings()
    }

    private func persistMeetings() {
        guard let data = try? JSONEncoder().encode(meetings) else { return }
        try? data.write(to: meetingsFileURL, options: .atomic)
    }
}
