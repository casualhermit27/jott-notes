import XCTest
@testable import jott

@MainActor
final class NoteStoreTests: XCTestCase {
    private var cleanupNoteIDs: [UUID] = []
    private var cleanupReminderIDs: [UUID] = []
    private var cleanupMeetingIDs: [UUID] = []

    override func tearDown() {
        let store = NoteStore.shared
        for id in cleanupNoteIDs {
            store.deleteNote(id)
        }
        for id in cleanupReminderIDs {
            store.deleteReminder(id)
        }
        for id in cleanupMeetingIDs {
            store.deleteMeeting(id)
        }

        cleanupNoteIDs.removeAll()
        cleanupReminderIDs.removeAll()
        cleanupMeetingIDs.removeAll()

        super.tearDown()
    }

    func testUpsertWritesMarkdownAndSupportsSearch() throws {
        let store = NoteStore.shared
        let note = Note(
            id: UUID(),
            text: "TEST-NOTE-\(UUID().uuidString) with #inbox",
            tags: ["inbox", "phase3"],
            isPinned: true
        )

        store.upsertNote(note)
        cleanupNoteIDs.append(note.id)

        let all = store.allNotes()
        let saved = try XCTUnwrap(all.first(where: { $0.id == note.id }))
        XCTAssertEqual(saved.tags, ["inbox", "phase3"])
        XCTAssertTrue(saved.isPinned)

        let search = store.searchNotes(query: "phase3")
        XCTAssertTrue(search.contains(where: { $0.id == note.id }))

        let fileURL = try XCTUnwrap(findMarkdownFile(for: note.id, in: store.notesFolder))
        let body = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(body.contains("id: \(note.id.uuidString)"))
        XCTAssertTrue(body.contains("tags: inbox, phase3"))
    }

    func testDeleteNoteIfEmptyRemovesWhitespaceOnlyNote() {
        let store = NoteStore.shared
        let note = Note(id: UUID(), text: "   \n\t", tags: ["empty"])

        store.upsertNote(note)
        store.deleteNoteIfEmpty(note.id)

        XCTAssertNil(store.note(for: note.id))
    }

    func testReminderLifecycleToggleSnoozeAndUpcomingFilter() {
        let store = NoteStore.shared
        let due = Date().addingTimeInterval(600)
        var reminder = Reminder(text: "TEST-REMINDER-\(UUID().uuidString)", dueDate: due, tags: ["ops"])

        store.saveReminder(reminder)
        cleanupReminderIDs.append(reminder.id)

        let upcoming = store.upcomingReminders()
        XCTAssertTrue(upcoming.contains(where: { $0.id == reminder.id }))

        let snoozedDate = Date().addingTimeInterval(3600)
        store.snoozeReminder(reminder.id, until: snoozedDate)

        let afterSnooze = store.allReminders()
        guard let snoozed = afterSnooze.first(where: { $0.id == reminder.id }) else {
            return XCTFail("Expected reminder after snooze")
        }
        XCTAssertEqual(Int(snoozed.dueDate.timeIntervalSince1970), Int(snoozedDate.timeIntervalSince1970))

        store.toggleReminder(reminder.id)
        let afterToggle = store.allReminders()
        guard let toggled = afterToggle.first(where: { $0.id == reminder.id }) else {
            return XCTFail("Expected reminder after toggle")
        }
        XCTAssertTrue(toggled.isCompleted)
    }

    func testMeetingLifecycleIncludesOnlyFutureInUpcoming() {
        let store = NoteStore.shared
        let past = Meeting(title: "TEST-PAST-\(UUID().uuidString)", participants: [], startTime: Date().addingTimeInterval(-3600))
        let future = Meeting(title: "TEST-FUTURE-\(UUID().uuidString)", participants: ["Alex"], startTime: Date().addingTimeInterval(3600))

        store.saveMeeting(past)
        store.saveMeeting(future)
        cleanupMeetingIDs.append(past.id)
        cleanupMeetingIDs.append(future.id)

        let upcoming = store.upcomingMeetings()
        XCTAssertTrue(upcoming.contains(where: { $0.id == future.id }))
        XCTAssertFalse(upcoming.contains(where: { $0.id == past.id }))
    }

    func testUpsertWithDuplicateSlugCreatesDistinctMarkdownFiles() throws {
        let store = NoteStore.shared
        let sharedPrefix = "duplicate slug \(UUID().uuidString.prefix(8))"
        let first = Note(id: UUID(), text: "\(sharedPrefix)\nfirst body", tags: [])
        let second = Note(id: UUID(), text: "\(sharedPrefix)\nsecond body", tags: [])

        store.upsertNote(first)
        store.upsertNote(second)
        cleanupNoteIDs.append(first.id)
        cleanupNoteIDs.append(second.id)

        let firstFile = try XCTUnwrap(findMarkdownFile(for: first.id, in: store.notesFolder))
        let secondFile = try XCTUnwrap(findMarkdownFile(for: second.id, in: store.notesFolder))

        XCTAssertNotEqual(firstFile.lastPathComponent, secondFile.lastPathComponent)
        XCTAssertTrue(secondFile.deletingPathExtension().lastPathComponent.hasPrefix(firstFile.deletingPathExtension().lastPathComponent))
    }

    func testPersistReminderWritesSchemaVersionContainer() throws {
        let store = NoteStore.shared
        let reminder = Reminder(text: "VERSION-CHECK-\(UUID().uuidString)", dueDate: Date().addingTimeInterval(300), tags: [])
        store.saveReminder(reminder)
        cleanupReminderIDs.append(reminder.id)

        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(component: "com.casualhermit.jott", directoryHint: .isDirectory)
        let remindersFileURL = appSupportDir.appending(component: "reminders.json")
        let json = try loadJSONObject(at: remindersFileURL)
        let version = try XCTUnwrap(json["version"] as? Int)
        let items = try XCTUnwrap(json["items"] as? [[String: Any]])

        XCTAssertEqual(version, 1)
        XCTAssertTrue(items.contains(where: { ($0["id"] as? String) == reminder.id.uuidString }))
    }

    func testPersistMeetingWritesSchemaVersionContainer() throws {
        let store = NoteStore.shared
        let meeting = Meeting(
            title: "VERSION-MEETING-\(UUID().uuidString)",
            participants: ["Taylor"],
            startTime: Date().addingTimeInterval(1200)
        )
        store.saveMeeting(meeting)
        cleanupMeetingIDs.append(meeting.id)

        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(component: "com.casualhermit.jott", directoryHint: .isDirectory)
        let meetingsFileURL = appSupportDir.appending(component: "meetings.json")
        let json = try loadJSONObject(at: meetingsFileURL)
        let version = try XCTUnwrap(json["version"] as? Int)
        let items = try XCTUnwrap(json["items"] as? [[String: Any]])

        XCTAssertEqual(version, 1)
        XCTAssertTrue(items.contains(where: { ($0["id"] as? String) == meeting.id.uuidString }))
    }

    func testReminderRoundTripCreateFetchDelete() {
        let store = NoteStore.shared
        let reminder = Reminder(
            text: "ROUNDTRIP-REMINDER-\(UUID().uuidString)",
            dueDate: Date().addingTimeInterval(900),
            tags: ["roundtrip", "integration"]
        )

        store.saveReminder(reminder)
        cleanupReminderIDs.append(reminder.id)
        XCTAssertTrue(store.allReminders().contains(where: { $0.id == reminder.id }))

        store.deleteReminder(reminder.id)
        cleanupReminderIDs.removeAll { $0 == reminder.id }
        XCTAssertFalse(store.allReminders().contains(where: { $0.id == reminder.id }))
    }

    func testMeetingRoundTripCreateFetchDelete() {
        let store = NoteStore.shared
        let meeting = Meeting(
            title: "ROUNDTRIP-MEETING-\(UUID().uuidString)",
            participants: ["Jordan", "Sam"],
            startTime: Date().addingTimeInterval(1800)
        )

        store.saveMeeting(meeting)
        cleanupMeetingIDs.append(meeting.id)
        XCTAssertTrue(store.allMeetings().contains(where: { $0.id == meeting.id }))

        store.deleteMeeting(meeting.id)
        cleanupMeetingIDs.removeAll { $0 == meeting.id }
        XCTAssertFalse(store.allMeetings().contains(where: { $0.id == meeting.id }))
    }

    func testParserToReminderStoreIntegrationPersistsParsedValues() {
        let store = NoteStore.shared
        let parseResult = NaturalLanguageParser.parse("Remind me to submit TPS report tomorrow at 4pm #ops")

        guard case let .reminder(text, dueDate, tags) = parseResult else {
            return XCTFail("Expected reminder parse result")
        }

        let reminder = Reminder(text: text, dueDate: dueDate, tags: tags)
        store.saveReminder(reminder)
        cleanupReminderIDs.append(reminder.id)

        guard let saved = store.allReminders().first(where: { $0.id == reminder.id }) else {
            return XCTFail("Expected saved reminder")
        }
        XCTAssertTrue(saved.text.lowercased().contains("submit tps report"))
        XCTAssertEqual(saved.tags, ["ops"])
        XCTAssertGreaterThan(saved.dueDate.timeIntervalSinceNow, 0)
    }

    func testCorruptedFrontmatterFileIsSkippedAndReported() throws {
        let store = NoteStore.shared
        let filename = "corrupt-frontmatter-\(UUID().uuidString).md"
        let fileURL = store.notesFolder.appending(component: filename)
        let corrupted = """
        ---
        id: \(UUID().uuidString)
        tags: bad
        This line is malformed and never closes frontmatter
        """
        try corrupted.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        store.reloadForTesting()

        XCTAssertFalse(store.allNotes().contains(where: { $0.fileURL == fileURL }))
        let error = store.consumeLastErrorMessage()
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("Skipped corrupted frontmatter") == true)
    }

    private func findMarkdownFile(for id: UUID, in folder: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []

        for file in files where file.pathExtension == "md" {
            if let content = try? String(contentsOf: file, encoding: .utf8),
               content.contains("id: \(id.uuidString)") {
                return file
            }
        }

        return nil
    }

    private func loadJSONObject(at fileURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: fileURL)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let json = object as? [String: Any] else {
            XCTFail("Expected top-level JSON dictionary at \(fileURL.lastPathComponent)")
            return [:]
        }
        return json
    }
}
