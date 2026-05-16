import Foundation
#if os(macOS)
import AppKit
#endif
import Combine
import CoreSpotlight

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
    private let foldersFileURL:   URL
    private let notesMetaFileURL: URL

    // In-memory metadata store: UUID → NoteMetadata
    private var notesMeta: [UUID: NoteMetadata] = [:]

    private struct NoteMetadata: Codable {
        var tags:      [String]
        var isPinned:  Bool
        var clusterId: UUID?
        var parentId:  UUID?
        var folderId:  UUID?
        var created:   Date
        var modified:  Date
        var filename:  String
        var deletedAt: Date?
    }
    @Published private(set) var clusters: [Cluster] = []
    @Published private(set) var folders: [NoteFolder] = []

    private let bookmarkKey = "jott_notesFolderBookmark"
    private var securityScopedActive = false

    /// UUID → slug filename mapping (e.g. UUID → "buy-milk.jott")
    private var noteFilenames: [UUID: String] = [:]

    /// Folder where .jott note files live. Falls back to <AppSupport>/Notes.
    private(set) var notesFolder: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
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
        foldersFileURL   = appSupportDir.appending(component: "folders.json")
        notesMetaFileURL = appSupportDir.appending(component: "notes-meta.json")

        // Resolve notes folder
#if os(macOS)
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
#else
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        notesFolder = docs.appending(component: "jott-notes", directoryHint: .isDirectory)
#endif

        do {
            try FileManager.default.createDirectory(at: notesFolder,
                                                    withIntermediateDirectories: true)
        } catch {
            NSLog("[Jott] Error creating notes folder: \(error.localizedDescription)")
        }
        load()
        migrateFromJSON()
        rebuildSpotlightIndex()
        CloudKitSyncManager.shared.sync(store: self)
    }

    // MARK: - Folder Selection

#if os(macOS)
    func selectNotesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Notes Folder"
        panel.prompt = "Choose"
        panel.message = "Jott will save your notes in this folder."
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
        for note in notesCache { writeNoteFile(note) }
    }
#endif

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

    /// Full nested path components for a folder (root → leaf)
    private func folderPathComponents(_ folderId: UUID) -> [String] {
        var components: [String] = []
        var current: UUID? = folderId
        var visited = Set<UUID>()
        while let cid = current {
            guard !visited.contains(cid) else { break }  // cycle guard
            visited.insert(cid)
            guard let folder = folders.first(where: { $0.id == cid }) else { break }
            let slug = slugify(folder.name)
            let part = slug.isEmpty ? cid.uuidString.prefix(8).lowercased() : slug
            components.insert(String(part), at: 0)
            current = folder.parentId
        }
        return components
    }

    /// Subfolder URL for a given folder (creates it if needed)
    private func folderDir(_ folderId: UUID) -> URL? {
        let parts = folderPathComponents(folderId)
        guard !parts.isEmpty else { return nil }
        let dir = parts.reduce(notesFolder) { $0.appending(component: $1, directoryHint: .isDirectory) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func generateFilename(for note: Note, in dir: URL) -> String {
        let slug = slugify(note.title)
        let base = slug.isEmpty ? "note-\(note.id.uuidString.prefix(4).lowercased())" : slug

        let existing = Set(noteFilenames.values)
        var candidate = "\(base).jott"
        if !existing.contains(candidate),
           !FileManager.default.fileExists(atPath: dir.appending(component: candidate).path) {
            return candidate
        }
        var counter = 2
        while existing.contains(candidate) ||
                FileManager.default.fileExists(atPath: dir.appending(component: candidate).path) {
            candidate = "\(base)-\(counter).jott"
            counter += 1
        }
        return candidate
    }

    private func fileURL(for note: Note) -> URL {
        let dir = note.folderId.flatMap { folderDir($0) } ?? notesFolder
        if let filename = noteFilenames[note.id] {
            // Upgrade .md → .jott filename if we stored the legacy name
            let jottName = filename.hasSuffix(".md")
                ? String(filename.dropLast(3)) + ".jott"
                : filename
            let candidate = dir.appending(component: jottName)
            let root      = notesFolder.appending(component: jottName)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            if FileManager.default.fileExists(atPath: root.path)      { return root }
            return candidate
        }
        let filename = generateFilename(for: note, in: dir)
        noteFilenames[note.id] = filename
        return dir.appending(component: filename)
    }

    // MARK: - MD helpers

    func attachmentsDirectoryURL() -> URL {
        notesFolder.appending(component: "attachments", directoryHint: .isDirectory)
    }

    private func attachmentsDir() -> URL {
        attachmentsDirectoryURL()
    }

    func attachmentURL(for path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reject absolute paths to prevent directory traversal outside the sandbox
        guard !trimmed.hasPrefix("/") else {
            return attachmentsDir()
        }

        let normalized = trimmed
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if normalized.isEmpty {
            return attachmentsDir()
        }

        let resolved: URL
        if normalized.hasPrefix("attachments/") {
            let relative = String(normalized.dropFirst("attachments/".count))
            resolved = relative
                .split(separator: "/")
                .map(String.init)
                .reduce(attachmentsDir()) { partial, component in
                    partial.appending(component: component)
                }
        } else {
            resolved = normalized
                .split(separator: "/")
                .map(String.init)
                .reduce(notesFolder) { partial, component in
                    partial.appending(component: component)
                }
        }

        // Final safety check: ensure the resolved path is within our sandbox
        let resolvedPath = resolved.standardizedFileURL.path
        let safePaths = [
            notesFolder.standardizedFileURL.path,
            attachmentsDir().standardizedFileURL.path
        ]
        guard safePaths.contains(where: { resolvedPath.hasPrefix($0) }) else {
            NSLog("[Jott] Blocked attachment path traversal attempt: \(path)")
            return attachmentsDir()
        }

        return resolved
    }

    private func writeNoteFile(_ note: Note) {
        struct NoteContent: Encodable {
            let blocks: [Block]
            let links:  [UUID]
        }
        do {
            try ensureNotesFolderExists()
            let url = fileURL(for: note)
            let content = NoteContent(blocks: note.blocks, links: note.links)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(content)
            try data.write(to: url, options: .atomic)
            // Update metadata sidecar
            notesMeta[note.id] = NoteMetadata(
                tags:      note.tags,
                isPinned:  note.isPinned,
                clusterId: note.clusterId,
                parentId:  note.parentId,
                folderId:  note.folderId,
                created:   note.timestamp,
                modified:  note.modifiedAt,
                filename:  noteFilenames[note.id] ?? url.lastPathComponent,
                deletedAt: note.deletedAt
            )
            saveNotesMeta()
            clearError()
        } catch {
            reportError(error, context: "saving note file")
        }
    }

    private func saveNotesMeta() {
        // Keyed by UUID string for JSON serialisation
        var dict: [String: NoteMetadata] = [:]
        for (id, meta) in notesMeta { dict[id.uuidString] = meta }
        do {
            let data = try JSONEncoder().encode(dict)
            try data.write(to: notesMetaFileURL, options: .atomic)
        } catch {
            reportError(error, context: "saving notes-meta.json")
        }
    }

    private func loadNotesMeta() {
        guard let data = try? Data(contentsOf: notesMetaFileURL),
              let dict = try? JSONDecoder().decode([String: NoteMetadata].self, from: data)
        else { return }
        notesMeta = Dictionary(uniqueKeysWithValues: dict.compactMap { k, v in
            guard let id = UUID(uuidString: k) else { return nil }
            return (id, v)
        })
    }

    private func readNoteFile(at url: URL) -> Note? {
        // ── .jott format: JSON {"blocks": [...], "links": [...]} ──
        if url.pathExtension == "jott" {
            return readNoteJott(at: url)
        }
        // ── .md format: migrate to .jott ──
        return readAndMigrateMD(at: url)
    }

    private func readNoteJott(at url: URL) -> Note? {
        struct NoteContent: Decodable {
            let blocks: [Block]
            let links:  [UUID]?
        }
        guard let data = try? Data(contentsOf: url) else {
            reportError(URLError(.cannotOpenFile), context: "reading note file \(url.lastPathComponent)")
            return nil
        }
        let content: NoteContent
        do {
            content = try JSONDecoder().decode(NoteContent.self, from: data)
        } catch {
            reportError(error, context: "decoding \(url.lastPathComponent)")
            return nil
        }
        let filename = url.lastPathComponent
        if let (id, meta) = notesMeta.first(where: { $0.value.filename == filename }) {
            noteFilenames[id] = filename
            return Note(id: id, blocks: content.blocks, links: content.links ?? [],
                        tags: meta.tags, timestamp: meta.created, modifiedAt: meta.modified,
                        fileURL: url, isPinned: meta.isPinned,
                        clusterId: meta.clusterId, parentId: meta.parentId,
                        folderId: meta.folderId, deletedAt: meta.deletedAt)
        }
        // No metadata — fresh note
        let id = UUID()
        noteFilenames[id] = filename
        notesMeta[id] = NoteMetadata(tags: [], isPinned: false, clusterId: nil,
                                     parentId: nil, folderId: nil,
                                     created: Date(), modified: Date(), filename: filename,
                                     deletedAt: nil)
        return Note(id: id, blocks: content.blocks, links: content.links ?? [], fileURL: url)
    }

    private func readAndMigrateMD(at url: URL) -> Note? {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            reportError(error, context: "reading note file \(url.lastPathComponent)")
            return nil
        }
        let mdFilename = url.lastPathComponent

        let note: Note?

        if !content.hasPrefix("---\n") {
            // Body-only .md with sidecar metadata
            if let (id, meta) = notesMeta.first(where: { $0.value.filename == mdFilename }) {
                noteFilenames[id] = mdFilename
                note = Note(id: id, text: content, tags: meta.tags,
                            timestamp: meta.created, modifiedAt: meta.modified,
                            fileURL: url, isPinned: meta.isPinned,
                            clusterId: meta.clusterId, parentId: meta.parentId,
                            folderId: meta.folderId, deletedAt: meta.deletedAt)
            } else {
                let id = UUID()
                noteFilenames[id] = mdFilename
                notesMeta[id] = NoteMetadata(tags: [], isPinned: false, clusterId: nil,
                                             parentId: nil, folderId: nil,
                                             created: Date(), modified: Date(),
                                             filename: mdFilename, deletedAt: nil)
                note = Note(id: id, text: content.trimmingCharacters(in: .whitespacesAndNewlines),
                            fileURL: url)
            }
        } else {
            // Legacy frontmatter — extract and migrate
            let iso = ISO8601DateFormatter()
            let parts = content.components(separatedBy: "\n---\n")
            guard parts.count >= 2 else {
                NSLog("[Jott] Skipped corrupted frontmatter in \(mdFilename).")
                return nil
            }
            let frontmatter = String(parts[0].dropFirst(4))
            let body = parts.dropFirst().joined(separator: "\n---\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var idStr: String?; var tagsStr = ""; var createdStr: String?; var modStr: String?
            var pinnedStr = "false"; var clusterStr: String?; var parentStr: String?; var folderStr: String?
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
                case "folder":   folderStr  = kv[1]
                default: break
                }
            }
            guard let idStr, let id = UUID(uuidString: idStr) else {
                NSLog("[Jott] Skipped note with invalid frontmatter id in \(mdFilename).")
                return nil
            }
            let tags      = tagsStr.isEmpty ? [] : tagsStr.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let created   = createdStr.flatMap { iso.date(from: $0) } ?? Date()
            let modified  = modStr.flatMap     { iso.date(from: $0) } ?? created
            let isPinned  = pinnedStr.lowercased() == "true"
            let clusterId = clusterStr.flatMap { UUID(uuidString: $0) }
            let parentId  = parentStr.flatMap  { UUID(uuidString: $0) }
            let folderId  = folderStr.flatMap  { UUID(uuidString: $0) }

            noteFilenames[id] = mdFilename
            notesMeta[id] = NoteMetadata(tags: tags, isPinned: isPinned, clusterId: clusterId,
                                         parentId: parentId, folderId: folderId,
                                         created: created, modified: modified,
                                         filename: mdFilename, deletedAt: nil)
            note = Note(id: id, text: body, tags: tags,
                        timestamp: created, modifiedAt: modified,
                        fileURL: url, isPinned: isPinned,
                        clusterId: clusterId, parentId: parentId,
                        folderId: folderId, deletedAt: nil)
        }

        // Migrate: write .jott counterpart and delete .md
        if let note {
            let jottURL = url.deletingPathExtension().appendingPathExtension("jott")
            let jottName = jottURL.lastPathComponent
            noteFilenames[note.id] = jottName
            notesMeta[note.id]?.filename = jottName
            writeNoteFile(note)
            try? FileManager.default.removeItem(at: url)
        }
        return note
    }

    private func loadNotes() {
        noteFilenames = [:]
        loadNotesMeta()
        let urls: [URL]
        do {
            try ensureNotesFolderExists()
            urls = try FileManager.default.contentsOfDirectory(
                at: notesFolder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )
        } catch {
            reportError(error, context: "loading notes directory")
            return
        }

        var allURLs: [URL] = urls.filter { $0.pathExtension == "jott" || $0.pathExtension == "md" }

        // Recursively scan subdirectories
        func collectNoteFiles(in dir: URL) {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
            )) ?? []
            for entry in entries {
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    collectNoteFiles(in: entry)
                } else if entry.pathExtension == "jott" || entry.pathExtension == "md" {
                    allURLs.append(entry)
                }
            }
        }
        for url in urls where (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            collectNoteFiles(in: url)
        }

        // Prefer .jott over .md when both exist for the same base name
        var seen = Set<String>()
        let prioritized = allURLs
            .sorted { a, _ in a.pathExtension == "jott" }
            .filter { url in
                let base = url.deletingPathExtension().path
                return seen.insert(base).inserted
            }

        notesCache = prioritized
            .compactMap { readNoteFile(at: $0) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        dedupeNotesCache()
    }

    private func load() {
        loadNotes()
        loadClusters()
        loadFolders()
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
                writeNoteFile(note)
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

    func upsertNote(_ note: Note, syncToCloud: Bool = true) {
        let isNew = !notesCache.contains(where: { $0.id == note.id })
        if isNew && !PurchaseManager.shared.hasAccess {
            PurchaseManager.shared.showPaywall()
            return
        }
        writeNoteFile(note)
        if let idx = notesCache.firstIndex(where: { $0.id == note.id }) {
            notesCache[idx] = note
        } else {
            notesCache.insert(note, at: 0)
        }
        dedupeNotesCache()
        if syncToCloud {
            CloudKitSyncManager.shared.push(note: note)
        }
        indexNoteInSpotlight(note)
        objectWillChange.send()
    }

    func allNotes() -> [Note] {
        activeNotes().sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.modifiedAt > b.modifiedAt
        }
    }

    func deletedNotes() -> [Note] {
        notesCache
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? $0.modifiedAt) > ($1.deletedAt ?? $1.modifiedAt) }
    }

    func allNotesIncludingDeleted() -> [Note] {
        notesCache.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func activeNotes() -> [Note] {
        notesCache.filter { $0.deletedAt == nil }
    }

    func refreshFromDisk() {
        load()
        purgeExpiredDeletedNotes()
        CloudKitSyncManager.shared.sync(store: self)
        objectWillChange.send()
    }

    private func purgeExpiredDeletedNotes() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let expired = notesCache.filter { $0.deletedAt != nil && ($0.deletedAt ?? Date()) < cutoff }.map { $0.id }
        for id in expired { permanentlyDeleteNote(id) }
    }

    func togglePin(_ id: UUID) {
        guard let idx = notesCache.firstIndex(where: { $0.id == id }) else { return }
        notesCache[idx].isPinned.toggle()
        notesCache[idx].modifiedAt = Date()
        writeNoteFile(notesCache[idx])
        CloudKitSyncManager.shared.push(note: notesCache[idx])
        objectWillChange.send()
    }

    func searchNotes(query: String) -> [Note] {
        let q = query.lowercased()
        return activeNotes().filter { note in
            note.text.lowercased().contains(q) ||
            note.tags.contains { $0.lowercased().contains(q) }
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func deleteNote(_ id: UUID, syncToCloud: Bool = true) {
        guard let idx = notesCache.firstIndex(where: { $0.id == id }) else { return }
        notesCache[idx].deletedAt = Date()
        notesCache[idx].modifiedAt = Date()
        notesCache[idx].isPinned = false
        writeNoteFile(notesCache[idx])
        if syncToCloud {
            CloudKitSyncManager.shared.push(note: notesCache[idx])
        }
        removeNoteFromSpotlight(id)
        objectWillChange.send()
    }

    func restoreNote(_ id: UUID, syncToCloud: Bool = true) {
        guard let idx = notesCache.firstIndex(where: { $0.id == id }) else { return }
        notesCache[idx].deletedAt = nil
        notesCache[idx].modifiedAt = Date()
        writeNoteFile(notesCache[idx])
        if syncToCloud {
            CloudKitSyncManager.shared.push(note: notesCache[idx])
        }
        indexNoteInSpotlight(notesCache[idx])
        objectWillChange.send()
    }

    func permanentlyDeleteNote(_ id: UUID, syncToCloud: Bool = true) {
        let existingNote = notesCache.first { $0.id == id }
        if let note = existingNote ?? notesCache.first(where: { $0.id == id }) {
            let url = note.fileURL ?? fileURL(for: note)
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                reportError(error, context: "deleting note file")
            }
        } else if let filename = noteFilenames[id] {
            let url = notesFolder.appending(component: filename)
            try? FileManager.default.removeItem(at: url)
        }
        noteFilenames.removeValue(forKey: id)
        notesMeta.removeValue(forKey: id)
        saveNotesMeta()
        notesCache.removeAll { $0.id == id }
        if syncToCloud {
            CloudKitSyncManager.shared.purgeNote(id: id, modifiedAt: Date())
        }
        removeNoteFromSpotlight(id)
        objectWillChange.send()
    }

    func deleteNoteIfEmpty(_ id: UUID) {
        if let note = notesCache.first(where: { $0.id == id }),
           note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            permanentlyDeleteNote(id)
        }
    }

#if os(macOS)
    func openNoteInEditor(_ note: Note) {
        let url = note.fileURL ?? fileURL(for: note)
        if !FileManager.default.fileExists(atPath: url.path) {
            writeNoteFile(note)
        }
        NSWorkspace.shared.open(notesFolder)
        NSWorkspace.shared.open(url)
    }

    func openNotesFolder() {
        NSWorkspace.shared.open(notesFolder)
    }
#endif

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
            let relativePath = "attachments/\(filename)"
            CloudKitSyncManager.shared.pushAttachment(relativePath: relativePath, fileURL: dest)
            return relativePath
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
        notesCache.first { $0.id == id && $0.deletedAt == nil }
    }

    func noteIncludingDeleted(for id: UUID) -> Note? {
        notesCache.first { $0.id == id }
    }

    // MARK: - Subnote helpers

    func rootNotes() -> [Note] {
        allNotes().filter { $0.parentId == nil }
    }

    func subnotes(of parentId: UUID) -> [Note] {
        let children = activeNotes().filter { $0.parentId == parentId }
        // If any have been explicitly ordered, use sortIndex; else fall back to modifiedAt
        let hasExplicitOrder = children.contains { $0.sortIndex > 0 }
        if hasExplicitOrder {
            return children.sorted { a, b in
                if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
                return a.modifiedAt < b.modifiedAt
            }
        }
        return children.sorted { $0.modifiedAt < $1.modifiedAt }
    }

    func reorderSubnotes(of parentId: UUID, ids: [UUID]) {
        for (index, id) in ids.enumerated() {
            guard let idx = notesCache.firstIndex(where: { $0.id == id }) else { continue }
            notesCache[idx].sortIndex = index + 1
            writeNoteFile(notesCache[idx])
        }
        objectWillChange.send()
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

    // MARK: - Folders

    private func loadFolders() {
        guard let data = try? Data(contentsOf: foldersFileURL) else { return }
        folders = (try? JSONDecoder().decode([NoteFolder].self, from: data)) ?? []
    }

    private func persistFolders() {
        do {
            let data = try JSONEncoder().encode(folders)
            try data.write(to: foldersFileURL, options: .atomic)
        } catch {
            reportError(error, context: "persisting folders")
        }
    }

    func createFolder(name: String, colorTag: FolderColorTag = .lavender, parentId: UUID? = nil) -> NoteFolder {
        let folder = NoteFolder(name: name, colorTag: colorTag, parentId: parentId)
        folders.append(folder)
        persistFolders()
        CloudKitSyncManager.shared.push(folder: folder)
        objectWillChange.send()
        return folder
    }

    func allFolders() -> [NoteFolder] {
        folders
    }

    func folder(for id: UUID) -> NoteFolder? {
        folders.first { $0.id == id }
    }

    func upsertFolder(_ folder: NoteFolder, syncToCloud: Bool = true) {
        if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[idx] = folder
        } else {
            folders.append(folder)
        }
        dedupeFolders()
        persistFolders()
        if syncToCloud {
            CloudKitSyncManager.shared.push(folder: folder)
        }
        objectWillChange.send()
    }

    func subfolders(of parentId: UUID?) -> [NoteFolder] {
        folders.filter { $0.parentId == parentId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        let oldDir = folderDir(id)
        folders[idx].name = name
        folders[idx].modifiedAt = Date()
        persistFolders()
        // Move the subfolder on disk if it already exists
        if let old = oldDir, let new = folderDir(id), old.path != new.path,
           FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: new)
        }
        CloudKitSyncManager.shared.push(folder: folders[idx])
        objectWillChange.send()
    }

    func saveFolder(_ folder: NoteFolder, syncToCloud: Bool = true) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        var updated = folder
        updated.modifiedAt = Date()
        folders[idx] = updated
        persistFolders()
        if syncToCloud {
            CloudKitSyncManager.shared.push(folder: updated)
        }
        objectWillChange.send()
    }

    func updateFolderColor(_ id: UUID, colorTag: FolderColorTag) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].colorTag = colorTag
        folders[idx].modifiedAt = Date()
        persistFolders()
        CloudKitSyncManager.shared.push(folder: folders[idx])
        objectWillChange.send()
    }

    func deleteFolder(_ id: UUID, syncToCloud: Bool = true) {
        // Move all notes in this folder back to root
        for idx in notesCache.indices where notesCache[idx].folderId == id {
            let oldURL = notesCache[idx].fileURL ?? fileURL(for: notesCache[idx])
            notesCache[idx].folderId = nil
            notesCache[idx].modifiedAt = Date()
            noteFilenames.removeValue(forKey: notesCache[idx].id)
            let newURL = fileURL(for: notesCache[idx])
            if FileManager.default.fileExists(atPath: oldURL.path), oldURL.path != newURL.path {
                try? FileManager.default.moveItem(at: oldURL, to: newURL)
                notesCache[idx].fileURL = newURL
            }
            writeNoteFile(notesCache[idx])
            CloudKitSyncManager.shared.push(note: notesCache[idx])
        }
        // Remove the now-empty subfolder
        if let dir = folderDir(id), FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        folders.removeAll { $0.id == id }
        persistFolders()
        if syncToCloud {
            CloudKitSyncManager.shared.deleteFolder(id: id)
        }
        objectWillChange.send()
    }

    func moveNote(_ noteId: UUID, toFolder folderId: UUID?) {
        guard let idx = notesCache.firstIndex(where: { $0.id == noteId }) else { return }
        let note = notesCache[idx]
        let oldURL = note.fileURL ?? fileURL(for: note)
        notesCache[idx].folderId = folderId
        notesCache[idx].modifiedAt = Date()
        // Clear cached filename so fileURL recalculates into the new dir
        noteFilenames.removeValue(forKey: noteId)
        let newURL = fileURL(for: notesCache[idx])
        // Physically move the file
        if FileManager.default.fileExists(atPath: oldURL.path), oldURL.path != newURL.path {
            try? FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: oldURL, to: newURL)
            notesCache[idx].fileURL = newURL
        }
        writeNoteFile(notesCache[idx])
        CloudKitSyncManager.shared.push(note: notesCache[idx])
        objectWillChange.send()
    }

    func notes(inFolder folderId: UUID) -> [Note] {
        activeNotes().filter { $0.folderId == folderId && $0.parentId == nil }
            .sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.modifiedAt > b.modifiedAt
            }
    }

    private func dedupeNotesCache() {
        var latest: [UUID: Note] = [:]
        for note in notesCache {
            if let current = latest[note.id] {
                latest[note.id] = note.modifiedAt >= current.modifiedAt ? note : current
            } else {
                latest[note.id] = note
            }
        }
        notesCache = latest.values.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.modifiedAt > b.modifiedAt
        }
        notesMeta = notesMeta.filter { latest[$0.key] != nil }
        noteFilenames = noteFilenames.filter { latest[$0.key] != nil }
    }

    private func dedupeFolders() {
        var latest: [UUID: NoteFolder] = [:]
        for folder in folders {
            if let current = latest[folder.id] {
                latest[folder.id] = folder.modifiedAt >= current.modifiedAt ? folder : current
            } else {
                latest[folder.id] = folder
            }
        }
        folders = latest.values.sorted { $0.createdAt < $1.createdAt }
    }


    // MARK: - Spotlight

    private let searchableIndex = CSSearchableIndex(name: "com.casualhermit.jott.notes")

    private func indexNoteInSpotlight(_ note: Note) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = note.title
        attributeSet.contentDescription = note.plainText
        attributeSet.keywords = note.tags
        attributeSet.contentCreationDate = note.timestamp
        attributeSet.contentModificationDate = note.modifiedAt

        let item = CSSearchableItem(
            uniqueIdentifier: note.id.uuidString,
            domainIdentifier: "note",
            attributeSet: attributeSet
        )

        searchableIndex.indexSearchableItems([item]) { error in
            if let error { NSLog("[Jott] Spotlight index error: \(error)") }
        }
    }

    private func removeNoteFromSpotlight(_ noteId: UUID) {
        searchableIndex.deleteSearchableItems(withIdentifiers: [noteId.uuidString]) { error in
            if let error { NSLog("[Jott] Spotlight delete error: \(error)") }
        }
    }

    private func rebuildSpotlightIndex() {
        let items = activeNotes().map { note -> CSSearchableItem in
            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
            attributeSet.title = note.title
            attributeSet.contentDescription = note.plainText
            attributeSet.keywords = note.tags
            attributeSet.contentCreationDate = note.timestamp
            attributeSet.contentModificationDate = note.modifiedAt
            return CSSearchableItem(
                uniqueIdentifier: note.id.uuidString,
                domainIdentifier: "note",
                attributeSet: attributeSet
            )
        }
        searchableIndex.indexSearchableItems(items) { error in
            if let error { NSLog("[Jott] Spotlight rebuild error: \(error)") }
        }
    }

    // MARK: - Export

    /// Exports all notes as Markdown files inside a ZIP archive.
    /// Returns the URL of the created ZIP file, or nil if creation failed.
    func exportAllNotesAsZip() -> URL? {
        let exportDir = FileManager.default.temporaryDirectory.appendingPathComponent("jott-export-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        for note in activeNotes() {
            let markdown = noteToMarkdown(note)
            let safeTitle = note.title.replacingOccurrences(of: "/", with: "-")
            let filename = "\(safeTitle).md"
            let fileURL = exportDir.appendingPathComponent(filename)
            try? markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("jott-export-\(Int(Date().timeIntervalSince1970)).zip")
        do {
            let coordinator = NSFileCoordinator()
            var zipError: NSError?
            coordinator.coordinate(readingItemAt: exportDir, options: .forUploading, error: &zipError) { url in
                try? FileManager.default.moveItem(at: url, to: zipURL)
            }
            if FileManager.default.fileExists(atPath: zipURL.path) {
                return zipURL
            }
        }
        return nil
    }

    func exportNoteAsMarkdown(_ note: Note) -> URL? {
        let markdown = noteToMarkdown(note)
        let safeTitle = note.title.replacingOccurrences(of: "/", with: "-")
        let filename = "\(safeTitle).md"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    private func noteToMarkdown(_ note: Note) -> String {
        var lines: [String] = []
        if !note.tags.isEmpty {
            lines.append(note.tags.map { "#\($0)" }.joined(separator: " "))
            lines.append("")
        }
        for block in note.blocks {
            switch block.type {
            case .paragraph:
                lines.append(block.plainText)
            case .heading:
                let prefix = String(repeating: "#", count: min(block.level, 6))
                lines.append("\(prefix) \(block.plainText)")
            case .bulletItem:
                lines.append("- \(block.plainText)")
            case .numberedItem:
                lines.append("1. \(block.plainText)")
            case .taskItem:
                lines.append("- [\(block.checked ? "x" : " ")] \(block.plainText)")
            case .quote:
                lines.append("> \(block.plainText)")
            case .codeBlock:
                lines.append("```")
                lines.append(block.plainText)
                lines.append("```")
            case .divider:
                lines.append("---")
            case .table:
                if !block.tableHeaders.isEmpty {
                    lines.append("| \(block.tableHeaders.joined(separator: " | ")) |")
                    lines.append("| \(block.tableHeaders.map { _ in "---" }.joined(separator: " | ")) |")
                    for row in block.tableRows {
                        lines.append("| \(row.joined(separator: " | ")) |")
                    }
                }
            case .toggle:
                lines.append("<details><summary>\(block.plainText)</summary>")
                lines.append(block.plainText)
                lines.append("</details>")
            case .image:
                break
            }
        }
        return lines.joined(separator: "\n")
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
