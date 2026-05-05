import CloudKit
import Foundation

@MainActor
final class CloudKitSyncManager {
    static let shared = CloudKitSyncManager()

    private let container = CKContainer(identifier: "iCloud.com.casualhermit.jott")
    private lazy var database = container.privateCloudDatabase
    private var isSyncing = false
    private var pendingSync = false

    private enum RecordType {
        static let note = "JottNote"
        static let folder = "JottFolder"
        static let attachment = "JottAttachment"
    }

    private enum NoteKey {
        static let text = "text"
        static let blocksJSON = "blocksJSON"
        static let links = "links"
        static let tags = "tags"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
        static let isPinned = "isPinned"
        static let clusterId = "clusterId"
        static let parentId = "parentId"
        static let sortIndex = "sortIndex"
        static let folderId = "folderId"
        static let isDeleted = "isDeleted"
        static let deletedAt = "deletedAt"
        static let purgedAt = "purgedAt"
    }

    private enum FolderKey {
        static let name = "name"
        static let colorTag = "colorTag"
        static let customColorHex = "customColorHex"
        static let createdAt = "createdAt"
        static let parentId = "parentId"
        static let modifiedAt = "modifiedAt"
        static let isDeleted = "isDeleted"
        static let purgedAt = "purgedAt"
    }

    private enum AttachmentKey {
        static let relativePath = "relativePath"
        static let file = "file"
        static let modifiedAt = "modifiedAt"
        static let isDeleted = "isDeleted"
    }

    private init() {}

    func setupSubscription() {
        Task {
            do {
                let subscription = CKDatabaseSubscription(subscriptionID: "jott-private-db-changes")
                let info = CKSubscription.NotificationInfo()
                info.shouldSendContentAvailable = true
                subscription.notificationInfo = info
                try await database.save(subscription)
                NSLog("[Jott] CloudKit subscription active")
            } catch {
                NSLog("[Jott] CloudKit subscription: \(error.localizedDescription)")
            }
        }
    }

    func sync(store: NoteStore) {
        guard !isSyncing else {
            pendingSync = true
            return
        }

        isSyncing = true
        Task {
            await performSync(store: store)
            await MainActor.run {
                isSyncing = false
                if pendingSync {
                    pendingSync = false
                    sync(store: store)
                }
            }
        }
    }

    func push(note: Note) {
        Task {
            do {
                try await saveNote(note)
            } catch {
                NSLog("[Jott] CloudKit note push failed: \(error.localizedDescription)")
            }
        }
    }

    func push(folder: NoteFolder) {
        Task {
            do {
                try await saveFolder(folder)
            } catch {
                NSLog("[Jott] CloudKit folder push failed: \(error.localizedDescription)")
            }
        }
    }

    func pushAttachment(relativePath: String, fileURL: URL) {
        Task {
            do {
                try await saveAttachment(relativePath: relativePath, fileURL: fileURL)
            } catch {
                NSLog("[Jott] CloudKit attachment push failed: \(error.localizedDescription)")
            }
        }
    }

    func deleteNote(id: UUID, modifiedAt: Date = Date()) {
        Task {
            do {
                let recordID = CKRecord.ID(recordName: noteRecordName(id))
                let record = try await existingRecord(id: recordID) ?? CKRecord(recordType: RecordType.note, recordID: recordID)
                record[NoteKey.modifiedAt] = modifiedAt as CKRecordValue
                record[NoteKey.isDeleted] = true as CKRecordValue
                record[NoteKey.deletedAt] = modifiedAt as CKRecordValue
                try await database.save(record)
            } catch {
                NSLog("[Jott] CloudKit note delete failed: \(error.localizedDescription)")
            }
        }
    }

    func purgeNote(id: UUID, modifiedAt: Date = Date()) {
        Task {
            do {
                let recordID = CKRecord.ID(recordName: noteRecordName(id))
                let record = try await existingRecord(id: recordID) ?? CKRecord(recordType: RecordType.note, recordID: recordID)
                record[NoteKey.modifiedAt] = modifiedAt as CKRecordValue
                record[NoteKey.isDeleted] = true as CKRecordValue
                record[NoteKey.deletedAt] = modifiedAt as CKRecordValue
                record[NoteKey.purgedAt] = modifiedAt as CKRecordValue
                try await database.save(record)
            } catch {
                NSLog("[Jott] CloudKit note purge failed: \(error.localizedDescription)")
            }
        }
    }

    func deleteFolder(id: UUID, modifiedAt: Date = Date()) {
        Task {
            do {
                let recordID = CKRecord.ID(recordName: folderRecordName(id))
                let record = try await existingRecord(id: recordID) ?? CKRecord(recordType: RecordType.folder, recordID: recordID)
                record[FolderKey.modifiedAt] = modifiedAt as CKRecordValue
                record[FolderKey.isDeleted] = true as CKRecordValue
                record[FolderKey.purgedAt] = modifiedAt as CKRecordValue
                try await database.save(record)
            } catch {
                NSLog("[Jott] CloudKit folder delete failed: \(error.localizedDescription)")
            }
        }
    }

    private func performSync(store: NoteStore) async {
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                NSLog("[Jott] iCloud unavailable for sync: \(String(describing: status))")
                return
            }

            // Seed the development schema before querying. On a brand-new CloudKit
            // container, querying a record type before the first save fails with
            // "Did not find record type".
            await seedSchema()
            try await pushLocalFolders(from: store)
            try await pushLocalNotes(from: store)
            try await pushLocalAttachments(from: store)

            let remoteFolders = try await fetchAll(recordType: RecordType.folder)
            mergeFolders(remoteFolders, into: store)

            let remoteNotes = try await fetchAll(recordType: RecordType.note)
            mergeNotes(remoteNotes, into: store)

            let remoteAttachments = try await fetchAll(recordType: RecordType.attachment)
            try mergeAttachments(remoteAttachments, into: store)
        } catch {
            NSLog("[Jott] CloudKit sync failed: \(error.localizedDescription)")
        }
    }

    private func mergeNotes(_ records: [CKRecord], into store: NoteStore) {
        for record in records {
            guard let id = uuid(fromRecordName: record.recordID.recordName, prefix: "note-") else { continue }
            let remoteModified = record[NoteKey.modifiedAt] as? Date ?? .distantPast

            if (record[NoteKey.isDeleted] as? Bool) == true {
                if record[NoteKey.purgedAt] as? Date != nil {
                    if let local = store.noteIncludingDeleted(for: id), local.modifiedAt > remoteModified {
                        continue
                    }
                    store.permanentlyDeleteNote(id, syncToCloud: false)
                    continue
                }
                if let remote = note(from: record, id: id) {
                    store.upsertNote(remote, syncToCloud: false)
                } else if let local = store.noteIncludingDeleted(for: id), local.modifiedAt <= remoteModified {
                    store.deleteNote(id, syncToCloud: false)
                }
                continue
            }

            guard let remote = note(from: record, id: id) else { continue }
            if let local = store.note(for: id), local.modifiedAt > remote.modifiedAt {
                continue
            }
            store.upsertNote(remote, syncToCloud: false)
        }
    }

    private func mergeFolders(_ records: [CKRecord], into store: NoteStore) {
        for record in records {
            guard let id = uuid(fromRecordName: record.recordID.recordName, prefix: "folder-") else { continue }
            let remoteModified = record[FolderKey.modifiedAt] as? Date ?? record.modificationDate ?? .distantPast

            if (record[FolderKey.isDeleted] as? Bool) == true {
                if record[FolderKey.purgedAt] as? Date != nil {
                    if let local = store.folder(for: id), local.modifiedAt > remoteModified {
                        continue
                    }
                    store.deleteFolder(id, syncToCloud: false)
                    continue
                }
                store.deleteFolder(id, syncToCloud: false)
                continue
            }

            guard let folder = folder(from: record, id: id) else { continue }
            if let local = store.folder(for: id), local.modifiedAt > remoteModified {
                continue
            }
            store.upsertFolder(folder, syncToCloud: false)
        }
    }

    private func pushLocalNotes(from store: NoteStore) async throws {
        var pushedCount = 0
        for note in store.allNotesIncludingDeleted() {
            do {
                try await saveNote(note)
                pushedCount += 1
            } catch {
                NSLog("[Jott] CloudKit note save failed for \(note.id): \(error.localizedDescription)")
            }
        }
        NSLog("[Jott] CloudKit pushed \(pushedCount) notes")
    }

    private func pushLocalFolders(from store: NoteStore) async throws {
        var pushedCount = 0
        for folder in store.allFolders() {
            do {
                try await saveFolder(folder)
                pushedCount += 1
            } catch {
                NSLog("[Jott] CloudKit folder save failed for \(folder.id): \(error.localizedDescription)")
            }
        }
        NSLog("[Jott] CloudKit pushed \(pushedCount) folders")
    }

    private func seedSchema() async {
        let now = Date()

        let folder = CKRecord(
            recordType: RecordType.folder,
            recordID: CKRecord.ID(recordName: "folder-bootstrap")
        )
        folder[FolderKey.name] = "Bootstrap" as CKRecordValue
        folder[FolderKey.colorTag] = FolderColorTag.lavender.rawValue as CKRecordValue
        folder[FolderKey.createdAt] = now as CKRecordValue
        folder[FolderKey.modifiedAt] = now as CKRecordValue
        folder[FolderKey.isDeleted] = true as CKRecordValue
        await saveBootstrapRecord(folder)

        let note = CKRecord(
            recordType: RecordType.note,
            recordID: CKRecord.ID(recordName: "note-bootstrap")
        )
        note[NoteKey.text] = "Bootstrap" as CKRecordValue
        note[NoteKey.blocksJSON] = "[]" as CKRecordValue
        note[NoteKey.tags] = ["bootstrap"] as CKRecordValue
        note[NoteKey.createdAt] = now as CKRecordValue
        note[NoteKey.modifiedAt] = now as CKRecordValue
        note[NoteKey.isPinned] = false as CKRecordValue
        note[NoteKey.sortIndex] = 0 as CKRecordValue
        note[NoteKey.isDeleted] = true as CKRecordValue
        note[NoteKey.deletedAt] = now as CKRecordValue
        await saveBootstrapRecord(note)

        let attachment = CKRecord(
            recordType: RecordType.attachment,
            recordID: CKRecord.ID(recordName: "attachment-bootstrap")
        )
        let bootstrapFileURL = FileManager.default.temporaryDirectory
            .appending(component: "jott-cloudkit-attachment-bootstrap.txt")
        do {
            if !FileManager.default.fileExists(atPath: bootstrapFileURL.path) {
                try "bootstrap".write(to: bootstrapFileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            NSLog("[Jott] CloudKit bootstrap attachment file failed: \(error.localizedDescription)")
            return
        }
        attachment[AttachmentKey.relativePath] = "attachments/bootstrap.txt" as CKRecordValue
        attachment[AttachmentKey.file] = CKAsset(fileURL: bootstrapFileURL)
        attachment[AttachmentKey.modifiedAt] = now as CKRecordValue
        attachment[AttachmentKey.isDeleted] = true as CKRecordValue
        await saveBootstrapRecord(attachment)
    }

    private func saveBootstrapRecord(_ record: CKRecord) async {
        do {
            _ = try await database.record(for: record.recordID)
            NSLog("[Jott] CloudKit bootstrap exists: \(record.recordType)")
        } catch let error as CKError where error.code == .unknownItem {
            do {
                try await database.save(record)
                NSLog("[Jott] CloudKit bootstrap saved: \(record.recordType)")
            } catch {
                NSLog("[Jott] CloudKit bootstrap save failed for \(record.recordType): \(error.localizedDescription)")
            }
        } catch {
            NSLog("[Jott] CloudKit bootstrap lookup failed for \(record.recordType): \(error.localizedDescription)")
        }
    }

    private func pushLocalAttachments(from store: NoteStore) async throws {
        let root = store.attachmentsDirectoryURL()
        guard FileManager.default.fileExists(atPath: root.path) else { return }

        let files = attachmentFiles(in: root)
        var pushedCount = 0
        for fileURL in files {
            let relative = relativeAttachmentPath(for: fileURL, root: root)
            do {
                try await saveAttachment(relativePath: relative, fileURL: fileURL)
                pushedCount += 1
            } catch {
                NSLog("[Jott] CloudKit attachment save failed for \(relative): \(error.localizedDescription)")
            }
        }
        NSLog("[Jott] CloudKit pushed \(pushedCount) attachments")
    }

    private func mergeAttachments(_ records: [CKRecord], into store: NoteStore) throws {
        for record in records {
            guard (record[AttachmentKey.isDeleted] as? Bool) != true,
                  let relativePath = record[AttachmentKey.relativePath] as? String,
                  let asset = record[AttachmentKey.file] as? CKAsset,
                  let sourceURL = asset.fileURL
            else { continue }

            let destination = store.attachmentURL(for: relativePath)
            let remoteModified = record[AttachmentKey.modifiedAt] as? Date ?? record.modificationDate ?? .distantPast
            let localModified = localModificationDate(for: destination)

            if let localModified, localModified > remoteModified {
                continue
            }

            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }
    }

    private func fetchAll(recordType: String) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))

        let firstPage: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)
        do {
            firstPage = try await database.records(matching: query, resultsLimit: CKQueryOperation.maximumResults)
        } catch {
            if isMissingRecordType(error) {
                NSLog("[Jott] CloudKit record type missing during first sync: \(recordType)")
                return []
            }
            throw error
        }
        records.append(contentsOf: firstPage.matchResults.compactMap { try? $0.1.get() })

        var cursor = firstPage.queryCursor
        while let nextCursor = cursor {
            let page = try await database.records(continuingMatchFrom: nextCursor, resultsLimit: CKQueryOperation.maximumResults)
            records.append(contentsOf: page.matchResults.compactMap { try? $0.1.get() })
            cursor = page.queryCursor
        }
        return records
    }

    private func isMissingRecordType(_ error: Error) -> Bool {
        let message = (error as NSError).localizedDescription
        return message.contains("Did not find record type")
            || message.contains("record type")
            && message.contains("not found")
    }

    private func existingRecord(id: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func saveNote(_ note: Note) async throws {
        let recordID = CKRecord.ID(recordName: noteRecordName(note.id))
        let record = try await existingRecord(id: recordID) ?? CKRecord(recordType: RecordType.note, recordID: recordID)
        if (record[NoteKey.isDeleted] as? Bool) == true,
           record[NoteKey.purgedAt] as? Date != nil {
            return
        }
        if let remoteModified = record[NoteKey.modifiedAt] as? Date,
           remoteModified > note.modifiedAt {
            return
        }
        apply(note: note, to: record)
        do {
            try await database.save(record)
        } catch let error as CKError where isRecordConflict(error) {
            try await retrySaveNoteAfterConflict(note, recordID: recordID, error: error)
        }
    }

    private func retrySaveNoteAfterConflict(_ note: Note, recordID: CKRecord.ID, error: CKError) async throws {
        let serverRecord: CKRecord
        if let changedRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
            serverRecord = changedRecord
        } else if let fetchedRecord = try await existingRecord(id: recordID) {
            serverRecord = fetchedRecord
        } else {
            serverRecord = CKRecord(recordType: RecordType.note, recordID: recordID)
        }

        if (serverRecord[NoteKey.isDeleted] as? Bool) == true,
           serverRecord[NoteKey.purgedAt] as? Date != nil {
            return
        }
        if let remoteModified = serverRecord[NoteKey.modifiedAt] as? Date,
           remoteModified > note.modifiedAt {
            return
        }

        apply(note: note, to: serverRecord)
        try await database.save(serverRecord)
    }

    private func isRecordConflict(_ error: CKError) -> Bool {
        error.code == .serverRecordChanged
            || error.localizedDescription.localizedCaseInsensitiveContains("oplock")
    }

    private func saveFolder(_ folder: NoteFolder) async throws {
        let recordID = CKRecord.ID(recordName: folderRecordName(folder.id))
        let record = try await existingRecord(id: recordID) ?? CKRecord(recordType: RecordType.folder, recordID: recordID)
        if (record[FolderKey.isDeleted] as? Bool) == true {
            return
        }
        if let remoteModified = record[FolderKey.modifiedAt] as? Date,
           remoteModified > folder.modifiedAt {
            return
        }
        apply(folder: folder, to: record)
        try await database.save(record)
    }

    private func saveAttachment(relativePath: String, fileURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let recordID = CKRecord.ID(recordName: attachmentRecordName(relativePath))
        let record = try await existingRecord(id: recordID) ?? CKRecord(recordType: RecordType.attachment, recordID: recordID)
        record[AttachmentKey.relativePath] = relativePath as CKRecordValue
        record[AttachmentKey.file] = CKAsset(fileURL: fileURL)
        record[AttachmentKey.modifiedAt] = (localModificationDate(for: fileURL) ?? Date()) as CKRecordValue
        record[AttachmentKey.isDeleted] = false as CKRecordValue
        try await database.save(record)
    }

    private func record(from note: Note) -> CKRecord {
        let record = CKRecord(recordType: RecordType.note, recordID: CKRecord.ID(recordName: noteRecordName(note.id)))
        apply(note: note, to: record)
        return record
    }

    private func apply(note: Note, to record: CKRecord) {
        // blocksJSON is the source of truth; text kept for cross-platform compat
        if let data = try? JSONEncoder().encode(note.blocks),
           let json = String(data: data, encoding: .utf8) {
            record[NoteKey.blocksJSON] = json as CKRecordValue
        }
        // Only set links when non-empty — CloudKit cannot infer the element type from []
        if !note.links.isEmpty {
            record[NoteKey.links] = note.links.map(\.uuidString) as CKRecordValue
        }
        record[NoteKey.text]       = note.text as CKRecordValue
        record[NoteKey.tags]       = note.tags as CKRecordValue
        record[NoteKey.createdAt]  = note.timestamp as CKRecordValue
        record[NoteKey.modifiedAt] = note.modifiedAt as CKRecordValue
        record[NoteKey.isPinned]   = note.isPinned as CKRecordValue
        record[NoteKey.clusterId]  = note.clusterId?.uuidString as CKRecordValue?
        record[NoteKey.parentId]   = note.parentId?.uuidString as CKRecordValue?
        record[NoteKey.sortIndex]  = note.sortIndex as CKRecordValue
        record[NoteKey.folderId]   = note.folderId?.uuidString as CKRecordValue?
        record[NoteKey.isDeleted]  = (note.deletedAt != nil) as CKRecordValue
        record[NoteKey.deletedAt]  = note.deletedAt as CKRecordValue?
        record[NoteKey.purgedAt]   = nil
    }

    private func record(from folder: NoteFolder) -> CKRecord {
        let record = CKRecord(recordType: RecordType.folder, recordID: CKRecord.ID(recordName: folderRecordName(folder.id)))
        apply(folder: folder, to: record)
        return record
    }

    private func apply(folder: NoteFolder, to record: CKRecord) {
        record[FolderKey.name] = folder.name as CKRecordValue
        record[FolderKey.colorTag] = folder.colorTag.rawValue as CKRecordValue
        record[FolderKey.customColorHex] = folder.customColorHex as CKRecordValue?
        record[FolderKey.createdAt] = folder.createdAt as CKRecordValue
        record[FolderKey.parentId] = folder.parentId?.uuidString as CKRecordValue?
        record[FolderKey.modifiedAt] = folder.modifiedAt as CKRecordValue
        record[FolderKey.isDeleted] = false as CKRecordValue
        record[FolderKey.purgedAt] = nil
    }

    private func note(from record: CKRecord, id: UUID) -> Note? {
        let createdAt  = record[NoteKey.createdAt]  as? Date ?? Date()
        let modifiedAt = record[NoteKey.modifiedAt] as? Date ?? record.modificationDate ?? createdAt
        let tags       = record[NoteKey.tags] as? [String] ?? []
        let links: [UUID] = (record[NoteKey.links] as? [String] ?? []).compactMap { UUID(uuidString: $0) }

        // Prefer structured blocks; fall back to parsing legacy text field
        let blocks: [Block]
        if let json = record[NoteKey.blocksJSON] as? String,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Block].self, from: data),
           !decoded.isEmpty {
            blocks = decoded
        } else if let text = record[NoteKey.text] as? String, !text.isEmpty {
            blocks = MarkdownConverter.parse(text)
        } else {
            return nil
        }

        return Note(
            id: id,
            blocks: blocks,
            links: links,
            tags: tags,
            timestamp: createdAt,
            modifiedAt: modifiedAt,
            isPinned: (record[NoteKey.isPinned] as? Bool) ?? false,
            clusterId: uuid(from: record[NoteKey.clusterId]),
            parentId: uuid(from: record[NoteKey.parentId]),
            sortIndex: (record[NoteKey.sortIndex] as? Int) ?? 0,
            folderId: uuid(from: record[NoteKey.folderId]),
            deletedAt: record[NoteKey.deletedAt] as? Date
        )
    }

    private func folder(from record: CKRecord, id: UUID) -> NoteFolder? {
        guard let name = record[FolderKey.name] as? String else { return nil }
        let colorTag = (record[FolderKey.colorTag] as? String).flatMap(FolderColorTag.init(rawValue:)) ?? .lavender
        let createdAt = record[FolderKey.createdAt] as? Date ?? Date()
        let modifiedAt = record[FolderKey.modifiedAt] as? Date ?? record.modificationDate ?? createdAt
        return NoteFolder(
            id: id,
            name: name,
            colorTag: colorTag,
            customColorHex: record[FolderKey.customColorHex] as? String,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            parentId: uuid(from: record[FolderKey.parentId])
        )
    }

    private func noteRecordName(_ id: UUID) -> String {
        "note-\(id.uuidString)"
    }

    private func folderRecordName(_ id: UUID) -> String {
        "folder-\(id.uuidString)"
    }

    private func attachmentRecordName(_ relativePath: String) -> String {
        let encoded = Data(relativePath.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "attachment-\(encoded)"
    }

    private func attachmentFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  ((try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false)
            else { return nil }
            return url
        }
    }

    private func relativeAttachmentPath(for fileURL: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let relative = filePath.hasPrefix(rootPath)
            ? String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : fileURL.lastPathComponent
        return "attachments/\(relative)"
    }

    private func localModificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func uuid(from value: CKRecordValue?) -> UUID? {
        guard let string = value as? String else { return nil }
        return UUID(uuidString: string)
    }

    private func uuid(fromRecordName name: String, prefix: String) -> UUID? {
        guard name.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(prefix.count)))
    }
}
