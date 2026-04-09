import Foundation
import AppKit
import Combine

@MainActor
final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    private var notesCache:  [Note] = []
    private var reminders:   [Reminder] = []
    @Published private(set) var lastErrorMessage: String?

    private let storageSchemaVersion = 1

    private let appSupportDir:    URL
    private let remindersFileURL: URL
    private let clustersFileURL:  URL
    @Published private(set) var clusters: [Cluster] = []

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
        do {
            try FileManager.default.createDirectory(at: appSupportDir,
                                                    withIntermediateDirectories: true)
        } catch {
            NSLog("[Jott] Error creating app support directory: \(error.localizedDescription)")
        }

        remindersFileURL = appSupportDir.appending(component: "reminders.json")
        clustersFileURL  = appSupportDir.appending(component: "clusters.json")

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

        do {
            try FileManager.default.createDirectory(at: notesFolder,
                                                    withIntermediateDirectories: true)
        } catch {
            NSLog("[Jott] Error creating notes folder: \(error.localizedDescription)")
        }
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
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            reportError(error, context: "saving folder bookmark")
        }

        // Start accessing the new folder
        _ = url.startAccessingSecurityScopedResource()
        notesFolder = url
        do {
            try FileManager.default.createDirectory(at: notesFolder,
                                                    withIntermediateDirectories: true)
        } catch {
            reportError(error, context: "creating selected notes folder")
        }
        // Re-persist all cached notes into new folder
        for note in notesCache { writeNoteMD(note) }
    }

    // MARK: - Slug helpers

    private func slugify(_ text: String) -> String {
        let lower = text.lowercased()
        // Replace non-alphanumeric characters with hyphens
        let slug = lower.unicodeScalars.map { scalar -> Character in
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
        if !existing.contains(candidate),
           !FileManager.default.fileExists(atPath: notesFolder.appending(component: candidate).path) {
            return candidate
        }
        var counter = 2
        while existing.contains(candidate) ||
                FileManager.default.fileExists(atPath: notesFolder.appending(component: candidate).path) {
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

    func attachmentURL(for path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }

        let normalized = trimmed
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if normalized.isEmpty {
            return attachmentsDir()
        }

        if normalized.hasPrefix("attachments/") {
            let relative = String(normalized.dropFirst("attachments/".count))
            return relative
                .split(separator: "/")
                .map(String.init)
                .reduce(attachmentsDir()) { partial, component in
                    partial.appending(component: component)
                }
        }

        return normalized
            .split(separator: "/")
            .map(String.init)
            .reduce(notesFolder) { partial, component in
                partial.appending(component: component)
            }
    }

    private func writeNoteMD(_ note: Note) {
        let iso = ISO8601DateFormatter()
        var fmLines = [
            "---",
            "id: \(note.id.uuidString)",
            "tags: \(note.tags.joined(separator: ", "))",
            "pinned: \(note.isPinned)",
        ]
        if let cid = note.clusterId  { fmLines.append("cluster: \(cid.uuidString)") }
        if let pid = note.parentId   { fmLines.append("parent: \(pid.uuidString)") }
        fmLines += [
            "created: \(iso.string(from: note.timestamp))",
            "modified: \(iso.string(from: note.modifiedAt))",
            "---",
            "",
        ]
        let fm = fmLines.joined(separator: "\n")
        let content = fm + note.text
        do {
            try ensureNotesFolderExists()
            try content.write(to: fileURL(for: note), atomically: true, encoding: .utf8)
            clearError()
        } catch {
            reportError(error, context: "saving note file")
        }
    }

    private func readNoteMD(at url: URL) -> Note? {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            reportError(error, context: "reading note file \(url.lastPathComponent)")
            return nil
        }
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
        guard parts.count >= 2 else {
            let message = "Skipped corrupted frontmatter in \(url.lastPathComponent)."
            NSLog("[Jott] \(message)")
            lastErrorMessage = message
            return nil
        }
        let frontmatter = String(parts[0].dropFirst(4))  // drop leading "---\n"
        let body = parts.dropFirst().joined(separator: "\n---\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var idStr: String?; var tagsStr = ""; var createdStr: String?; var modStr: String?; var pinnedStr = "false"; var clusterStr: String?; var parentStr: String?
        for line in frontmatter.components(separatedBy: "\n") {
            let kv = line.split(separator: ":", maxSplits: 1)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "id":       idStr      = kv[1]
            case "tags":     tagsStr    = kv[1]
            case "pinned":   pinnedStr  = kv[1]
            case "created":  createdStr = kv[1]
            case "modified": modStr     = kv[1]
            case "cluster":  clusterStr = kv[1]
            case "parent":   parentStr  = kv[1]
            default: break
            }
        }

        guard let idStr, let id = UUID(uuidString: idStr) else {
            let message = "Skipped note with invalid frontmatter id in \(url.lastPathComponent)."
            NSLog("[Jott] \(message)")
            lastErrorMessage = message
            return nil
        }
        let tags     = tagsStr.isEmpty ? [] : tagsStr.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let created  = createdStr.flatMap { iso.date(from: $0) } ?? Date()
        let modified = modStr.flatMap     { iso.date(from: $0) } ?? created

        // Register the filename for this UUID
        noteFilenames[id] = url.lastPathComponent

        let isPinned  = pinnedStr.lowercased() == "true"
        let clusterId = clusterStr.flatMap { UUID(uuidString: $0) }
        let parentId  = parentStr.flatMap  { UUID(uuidString: $0) }
        return Note(id: id, text: body, tags: tags,
                    timestamp: created, modifiedAt: modified, fileURL: url,
                    isPinned: isPinned, clusterId: clusterId, parentId: parentId)
    }

    private func loadNotes() {
        noteFilenames = [:]
        let urls: [URL]
        do {
            try ensureNotesFolderExists()
            urls = try FileManager.default.contentsOfDirectory(
                at: notesFolder,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            reportError(error, context: "loading notes directory")
            return
        }
        notesCache = urls
            .filter { $0.pathExtension == "md" }
            .compactMap { readNoteMD(at: $0) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func load() {
        loadNotes()
        loadClusters()
        if let data = try? Data(contentsOf: remindersFileURL) {
            if let container = try? JSONDecoder().decode(StorageContainer<Reminder>.self, from: data) {
                reminders = container.items
            } else if let legacy = try? JSONDecoder().decode([Reminder].self, from: data) {
                reminders = legacy
            } else {
                reportErrorMessage("Could not decode reminders.json; using empty reminders list.")
                reminders = []
            }
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
        do {
            try FileManager.default.removeItem(at: oldJSON)
        } catch {
            reportError(error, context: "removing legacy notes.json")
        }
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
        objectWillChange.send()
    }

    func allNotes() -> [Note] {
        notesCache.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.modifiedAt > b.modifiedAt
        }
    }

    func refreshFromDisk() {
        load()
        objectWillChange.send()
    }

    func togglePin(_ id: UUID) {
        guard let idx = notesCache.firstIndex(where: { $0.id == id }) else { return }
        notesCache[idx].isPinned.toggle()
        writeNoteMD(notesCache[idx])
        objectWillChange.send()
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
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                reportError(error, context: "deleting note file")
            }
        }
        noteFilenames.removeValue(forKey: id)
        notesCache.removeAll { $0.id == id }
        objectWillChange.send()
    }

    func deleteNoteIfEmpty(_ id: UUID) {
        if let note = notesCache.first(where: { $0.id == id }),
           note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deleteNote(id)
        }
    }

    func openNoteInEditor(_ note: Note) {
        let url = note.fileURL ?? fileURL(for: note)
        if !FileManager.default.fileExists(atPath: url.path) {
            writeNoteMD(note)
        }
        NSWorkspace.shared.open(url)
    }

    func openNotesFolder() {
        NSWorkspace.shared.open(notesFolder)
    }

    // MARK: - Attachments

    /// Copies a local file into the attachments folder, deduplicating the name if needed.
    /// Returns the relative `attachments/filename` path, or nil on failure.
    func saveFileAttachment(from sourceURL: URL) -> String? {
        let dir = attachmentsDir()
        var name = sourceURL.lastPathComponent
        // Deduplicate: if a file with that name already exists, append a counter
        var candidate = name
        var counter = 1
        let ext = sourceURL.pathExtension
        let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        while FileManager.default.fileExists(atPath: dir.appending(component: candidate).path) {
            candidate = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            counter += 1
        }
        name = candidate
        guard let data = try? Data(contentsOf: sourceURL) else { return nil }
        return saveAttachment(data: data, filename: name)
    }

    func saveAttachment(data: Data, filename: String) -> String? {
        let dir = attachmentsDir()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            reportError(error, context: "creating attachments directory")
            return nil
        }
        let dest = dir.appending(component: filename)
        do {
            try data.write(to: dest, options: .atomic)
            clearError()
            return "attachments/\(filename)"
        } catch {
            reportError(error, context: "saving attachment")
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

    func snoozeReminder(_ id: UUID, until date: Date) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[idx].dueDate = date
        persistReminders()
    }


    func note(for id: UUID) -> Note? {
        notesCache.first { $0.id == id }
    }

    // MARK: - Subnote helpers

    func rootNotes() -> [Note] {
        allNotes().filter { $0.parentId == nil }
    }

    func subnotes(of parentId: UUID) -> [Note] {
        notesCache
            .filter { $0.parentId == parentId }
            .sorted { $0.modifiedAt < $1.modifiedAt }
    }

    func subnoteCount(of parentId: UUID) -> Int {
        notesCache.filter { $0.parentId == parentId }.count
    }

    private func persistReminders() {
        do {
            let payload = StorageContainer(version: storageSchemaVersion, items: reminders)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: remindersFileURL, options: .atomic)
            clearError()
        } catch {
            reportError(error, context: "persisting reminders")
        }
    }

    func consumeLastErrorMessage() -> String? {
        defer { lastErrorMessage = nil }
        return lastErrorMessage
    }

    private func ensureNotesFolderExists() throws {
        if !FileManager.default.fileExists(atPath: notesFolder.path) {
            try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
        }
    }

    private func reportError(_ error: Error, context: String) {
        let message = "Error \(context): \(error.localizedDescription)"
        reportErrorMessage(message)
    }

    private func reportErrorMessage(_ message: String) {
        NSLog("[Jott] \(message)")
        lastErrorMessage = message
    }

    private func clearError() {
        lastErrorMessage = nil
    }

    // MARK: - Clusters

    private func loadClusters() {
        guard let data = try? Data(contentsOf: clustersFileURL) else { return }
        clusters = (try? JSONDecoder().decode([Cluster].self, from: data)) ?? []
    }

    private func persistClusters() {
        do {
            let data = try JSONEncoder().encode(clusters)
            try data.write(to: clustersFileURL, options: .atomic)
        } catch {
            reportError(error, context: "persisting clusters")
        }
    }

    func saveCluster(_ cluster: Cluster) {
        if let idx = clusters.firstIndex(where: { $0.id == cluster.id }) {
            clusters[idx] = cluster
        } else {
            clusters.append(cluster)
        }
        persistClusters()
        objectWillChange.send()
    }

    func deleteCluster(_ id: UUID) {
        clusters.removeAll { $0.id == id }
        persistClusters()
        objectWillChange.send()
    }

    func nextClusterColor() -> String {
        Cluster.palette[clusters.count % Cluster.palette.count]
    }


#if DEBUG
    /// Test-only helper to reload persisted content from disk.
    func reloadForTesting() {
        load()
    }
#endif
}

private struct StorageContainer<T: Codable>: Codable {
    let version: Int
    var items: [T]
}
