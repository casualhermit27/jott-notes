import AppIntents
import Foundation

struct OpenJottCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Jott Capture"
    static var description = IntentDescription("Opens Jott directly into the quick capture surface.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        JottQuickCaptureCenter.shared.requestCapture()
        return .result()
    }
}

struct CreateJottNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Jott Note"
    static var description = IntentDescription("Creates a note in Jott without opening the app.")

    @Parameter(title: "Text")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Create note with \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Nothing to save.")
        }

        let note = Note(id: UUID(), text: trimmed)
        NoteStore.shared.upsertNote(note)
        return .result(dialog: "Saved to Jott.")
    }
}

struct JottMobileShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenJottCaptureIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Open \(.applicationName) capture",
                "Jott something in \(.applicationName)"
            ],
            shortTitle: "Capture",
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: CreateJottNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "Save a note in \(.applicationName)"
            ],
            shortTitle: "Save Note",
            systemImageName: "note.text.badge.plus"
        )
    }
}
