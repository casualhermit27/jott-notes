import SwiftUI

/// Shown as a sheet when the user taps "Link note" in NoteDetailContent.
/// Displays all notes (excluding the current one) with search.
/// Tapping a row links it and dismisses.
struct NoteLinkPickerView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let sourceNoteId: UUID
    let alreadyLinked: [UUID]
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var candidates: [Note] {
        let all = viewModel.getAllNotes().filter { $0.id != sourceNoteId }
        if searchText.isEmpty { return all }
        let q = searchText.lowercased()
        return all.filter { $0.text.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Link a note")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField("Search notes...", text: $searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(7)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Divider()

            // Note list
            ScrollView {
                VStack(spacing: 0) {
                    if candidates.isEmpty {
                        Text("No notes found")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(20)
                    } else {
                        ForEach(candidates) { note in
                            Button(action: {
                                viewModel.linkNote(sourceNoteId, to: note.id)
                                dismiss()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: alreadyLinked.contains(note.id) ? "link.circle.fill" : "link.circle")
                                        .font(.system(size: 14))
                                        .foregroundColor(alreadyLinked.contains(note.id) ? .jottGreen : .secondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(note.text.components(separatedBy: "\n").first ?? note.text)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                            .foregroundColor(.primary)

                                        Text(relativeDate(note.modifiedAt))
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if alreadyLinked.contains(note.id) {
                                        Text("linked")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.jottGreen)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.jottGreen.opacity(0.12))
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: 340)
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }
}
