import SwiftUI
import AppKit

struct DetailView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ZStack {
            // Background - light or dark
            if viewModel.isDarkMode {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.12, green: 0.12, blue: 0.13),
                        Color(red: 0.15, green: 0.14, blue: 0.16)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.97, green: 0.98, blue: 0.95),
                        Color(red: 0.96, green: 0.97, blue: 0.98)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    Button(action: {
                        viewModel.selectedNote = nil
                        viewModel.selectedReminder = nil
                        viewModel.selectedMeeting = nil
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(viewModel.isDarkMode ? Color(red: 0.75, green: 0.82, blue: 0.75) : Color(red: 0.45, green: 0.75, blue: 0.55))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if let note = viewModel.selectedNote, !viewModel.isEditingNote {
                        // Pin toggle
                        Button(action: { viewModel.togglePin(note) }) {
                            Image(systemName: note.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(note.isPinned ? .orange : (viewModel.isDarkMode ? Color(red: 0.75, green: 0.82, blue: 0.75) : Color(red: 0.45, green: 0.75, blue: 0.55)))
                        }
                        .buttonStyle(.plain)

                        // Open in editor (Cmd+O)
                        Button(action: { viewModel.openNoteInEditor(note) }) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(viewModel.isDarkMode ? Color(red: 0.75, green: 0.82, blue: 0.75) : Color(red: 0.45, green: 0.75, blue: 0.55))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("o", modifiers: .command)

                        // Copy note text
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(note.text, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(viewModel.isDarkMode ? Color(red: 0.75, green: 0.82, blue: 0.75) : Color(red: 0.45, green: 0.75, blue: 0.55))
                        }
                        .buttonStyle(.plain)

                        Button(action: { viewModel.startEditingNote(note) }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(viewModel.isDarkMode ? Color(red: 0.75, green: 0.82, blue: 0.75) : Color(red: 0.45, green: 0.75, blue: 0.55))
                        }
                        .buttonStyle(.plain)

                        // Delete note (Cmd+Delete)
                        Button(action: {
                            viewModel.deleteNote(note.id)
                            viewModel.selectedNote = nil
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.red.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.delete, modifiers: .command)
                    } else if viewModel.isEditingNote {
                        HStack(spacing: 6) {
                            Button(action: { viewModel.saveEditedNote(viewModel.selectedNote!) }) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)

                            Button(action: { viewModel.cancelEditingNote() }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let _ = viewModel.selectedNote, !viewModel.isEditingNote {
                        Text("NOTE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.75, green: 0.82, blue: 0.75),
                                        Color(red: 0.78, green: 0.84, blue: 0.78),
                                        Color(red: 0.72, green: 0.80, blue: 0.72),
                                        Color(red: 0.76, green: 0.83, blue: 0.76),
                                        Color(red: 0.74, green: 0.81, blue: 0.74)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(5)
                    } else if let _ = viewModel.selectedReminder {
                        Text("REMINDER")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.85, green: 0.65, blue: 0.75),
                                        Color(red: 0.88, green: 0.70, blue: 0.78),
                                        Color(red: 0.82, green: 0.62, blue: 0.72),
                                        Color(red: 0.86, green: 0.68, blue: 0.76),
                                        Color(red: 0.84, green: 0.64, blue: 0.74)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(5)
                    } else if let _ = viewModel.selectedMeeting {
                        Text("MEETING")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.92, green: 0.72, blue: 0.62),
                                        Color(red: 0.94, green: 0.76, blue: 0.68),
                                        Color(red: 0.90, green: 0.70, blue: 0.60),
                                        Color(red: 0.93, green: 0.74, blue: 0.65),
                                        Color(red: 0.91, green: 0.71, blue: 0.61)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(5)
                    }
                }
                .padding(12)
                .background(viewModel.isDarkMode ? Color.white.opacity(0.05) : Color.white.opacity(0.8))
                .border(Color.gray.opacity(viewModel.isDarkMode ? 0.2 : 0.1), width: 0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let note = viewModel.selectedNote {
                            NoteDetailContent(note: note, viewModel: viewModel)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        } else if let reminder = viewModel.selectedReminder {
                            ReminderDetailContent(reminder: reminder, viewModel: viewModel)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        } else if let meeting = viewModel.selectedMeeting {
                            MeetingDetailContent(meeting: meeting, viewModel: viewModel)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}

struct NoteDetailContent: View {
    let note: Note
    @ObservedObject var viewModel: OverlayViewModel
    @State private var showingLinkPicker = false
    @State private var showMarkdownPreview = false

    private var wordCount: Int {
        note.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
    private var readingTime: String {
        let mins = max(1, wordCount / 200)
        return "\(mins) min read"
    }

    var linkedNotes: [Note] { viewModel.linkedNotes(for: note) }
    var backlinks: [Note]   { viewModel.backlinks(for: note) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if viewModel.isEditingNote {
                TextEditor(text: $viewModel.editingNoteText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(viewModel.isDarkMode ? .white : .black)
                    .frame(minHeight: 80)
                    .padding(7)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.75)
                    )
            } else {
                HStack(alignment: .top, spacing: 0) {
                    Group {
                        if showMarkdownPreview,
                           let attrStr = try? AttributedString(markdown: note.text) {
                            Text(attrStr)
                                .font(.system(size: 15))
                                .lineSpacing(2)
                        } else {
                            Text(note.text)
                                .font(.system(size: 16, weight: .semibold))
                                .lineSpacing(1.5)
                        }
                    }
                    .foregroundColor(viewModel.isDarkMode ? .white : .black)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showMarkdownPreview.toggle() }
                    } label: {
                        Image(systemName: showMarkdownPreview ? "text.alignleft" : "doc.richtext")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(showMarkdownPreview ? Color.accentColor.opacity(0.7) : .secondary.opacity(0.35))
                            .padding(5)
                            .background(showMarkdownPreview ? Color.accentColor.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 7) {
                DetailInfoRow(label: "Created", value: formatDate(note.timestamp), isDarkMode: viewModel.isDarkMode)
                DetailInfoRow(label: "Modified", value: formatDate(note.modifiedAt), isDarkMode: viewModel.isDarkMode)
                DetailInfoRow(label: "Words", value: "\(wordCount)  ·  \(readingTime)", isDarkMode: viewModel.isDarkMode)
            }

            if !note.tags.isEmpty {
                Divider()
                    .padding(.vertical, 3)

                VStack(alignment: .leading, spacing: 7) {
                    Text("TAGS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                        .tracking(0.5)

                    FlowLayout(spacing: 6) {
                        ForEach(note.tags, id: \.self) { tag in
                            Button {
                                viewModel.setTagFilter(tag)
                                viewModel.selectedNote = nil
                            } label: {
                                Text("#\(tag)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0.75, green: 0.82, blue: 0.75),
                                                Color(red: 0.78, green: 0.84, blue: 0.78),
                                                Color(red: 0.72, green: 0.80, blue: 0.72)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                            .help("Filter notes by #\(tag)")
                        }
                    }
                }
            }

            // MARK: Linked Notes
            Divider()
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("LINKED NOTES")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                        .tracking(0.5)
                    Spacer()
                    Button(action: { showingLinkPicker = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Link")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.jottGreen)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.jottGreen.opacity(0.1))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }

                if linkedNotes.isEmpty && backlinks.isEmpty {
                    Text("No linked notes yet. Type [[ to link.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    // Forward links
                    ForEach(linkedNotes) { linked in
                        LinkedNoteChip(
                            note: linked,
                            isDarkMode: viewModel.isDarkMode,
                            onTap: { viewModel.selectedNote = linked },
                            onRemove: { viewModel.unlinkNote(note.id, from: linked.id) }
                        )
                    }
                    // Backlinks (read-only — other notes that point here)
                    if !backlinks.isEmpty {
                        Text("BACKLINKS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)
                            .padding(.top, 4)
                        ForEach(backlinks) { bl in
                            LinkedNoteChip(
                                note: bl,
                                isDarkMode: viewModel.isDarkMode,
                                onTap: { viewModel.selectedNote = bl },
                                onRemove: nil
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(
                    gradient: Gradient(colors: viewModel.isDarkMode ? [
                        Color(red: 0.20, green: 0.20, blue: 0.21),
                        Color(red: 0.23, green: 0.22, blue: 0.24)
                    ] : [
                        Color(red: 0.98, green: 0.995, blue: 0.96),
                        Color(red: 0.97, green: 0.99, blue: 0.98)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.gray.opacity(viewModel.isDarkMode ? 0.2 : 0.1), lineWidth: 0.5))
        .sheet(isPresented: $showingLinkPicker) {
            NoteLinkPickerView(
                viewModel: viewModel,
                sourceNoteId: note.id,
                alreadyLinked: note.linkedNoteIds
            )
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct LinkedNoteChip: View {
    let note: Note
    let isDarkMode: Bool
    let onTap: () -> Void
    let onRemove: (() -> Void)?
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.jottGreen)
                    Text(note.text.components(separatedBy: "\n").first ?? note.text)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(isDarkMode ? .white : .black)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.55))
                }
            }
            .buttonStyle(.plain)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.jottGreen.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(hovered ? 0.12 : 0), radius: hovered ? 6 : 0, x: 0, y: 2)
        .scaleEffect(hovered ? 1.01 : 1.0)
        .onHover { h in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.82)) { hovered = h }
        }
    }
}

struct ReminderDetailContent: View {
    let reminder: Reminder
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .stroke(Color(red: 0.4, green: 0.65, blue: 0.95).opacity(0.2), lineWidth: 0.75)
                    Image(systemName: "bell")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 0.4, green: 0.65, blue: 0.95))
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.text)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(viewModel.isDarkMode ? .white : .black)
                    Text(reminder.isCompleted ? "COMPLETED" : "PENDING")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(reminder.isCompleted ? .green : Color(red: 0.4, green: 0.65, blue: 0.95))
                        .tracking(0.5)
                }
            }

            Divider()
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 7) {
                DetailInfoRow(label: "Due Date", value: formatDateTime(reminder.dueDate), isDarkMode: viewModel.isDarkMode)
                DetailInfoRow(label: "Status", value: reminder.isCompleted ? "Completed" : "Pending", isDarkMode: viewModel.isDarkMode)
                DetailInfoRow(label: "Created", value: formatDate(reminder.createdAt), isDarkMode: viewModel.isDarkMode)
            }

            // Snooze — only shown for pending, non-overdue intent (always show for pending)
            if !reminder.isCompleted {
                Divider()
                    .padding(.vertical, 3)

                VStack(alignment: .leading, spacing: 8) {
                    Text("SNOOZE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                        .tracking(0.5)

                    HStack(spacing: 8) {
                        SnoozeButton(label: "30 min") {
                            viewModel.snoozeReminder(reminder, minutes: 30)
                        }
                        SnoozeButton(label: "1 hour") {
                            viewModel.snoozeReminder(reminder, minutes: 60)
                        }
                        SnoozeButton(label: "Tomorrow 9am") {
                            viewModel.snoozeReminderToTomorrow(reminder)
                        }
                    }
                }
            }

            if !reminder.tags.isEmpty {
                Divider()
                    .padding(.vertical, 3)

                VStack(alignment: .leading, spacing: 7) {
                    Text("TAGS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                        .tracking(0.5)

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(reminder.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.85, green: 0.65, blue: 0.75),
                                            Color(red: 0.88, green: 0.70, blue: 0.78),
                                            Color(red: 0.82, green: 0.62, blue: 0.72)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(
                    gradient: Gradient(colors: viewModel.isDarkMode ? [
                        Color(red: 0.20, green: 0.20, blue: 0.21),
                        Color(red: 0.23, green: 0.22, blue: 0.24)
                    ] : [
                        Color(red: 0.96, green: 0.98, blue: 1.0),
                        Color(red: 0.97, green: 0.995, blue: 1.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.gray.opacity(viewModel.isDarkMode ? 0.2 : 0.1), lineWidth: 0.5))
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct MeetingDetailContent: View {
    let meeting: Meeting
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color(red: 1.0, green: 0.65, blue: 0.3).opacity(0.2), lineWidth: 1)
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.65, blue: 0.3))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(viewModel.isDarkMode ? .white : .black)
                    Text("\(meeting.duration) min")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.gray)
                }
            }

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                DetailInfoRow(label: "Start Time", value: formatDateTime(meeting.startTime), isDarkMode: viewModel.isDarkMode)
                DetailInfoRow(label: "Duration", value: "\(meeting.duration) minutes", isDarkMode: viewModel.isDarkMode)
                DetailInfoRow(label: "Created", value: formatDate(meeting.createdAt), isDarkMode: viewModel.isDarkMode)
            }

            if !meeting.participants.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("PARTICIPANTS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                        .tracking(0.5)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(meeting.participants, id: \.self) { participant in
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(participant)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.92, green: 0.72, blue: 0.62),
                                        Color(red: 0.94, green: 0.76, blue: 0.68),
                                        Color(red: 0.90, green: 0.70, blue: 0.60)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            if !meeting.tags.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("TAGS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                        .tracking(0.5)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(meeting.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.92, green: 0.72, blue: 0.62),
                                            Color(red: 0.94, green: 0.76, blue: 0.68),
                                            Color(red: 0.90, green: 0.70, blue: 0.60)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(
                    gradient: Gradient(colors: viewModel.isDarkMode ? [
                        Color(red: 0.20, green: 0.20, blue: 0.21),
                        Color(red: 0.23, green: 0.22, blue: 0.24)
                    ] : [
                        Color(red: 1.0, green: 0.97, blue: 0.94),
                        Color(red: 1.0, green: 0.985, blue: 0.97)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.gray.opacity(viewModel.isDarkMode ? 0.2 : 0.1), lineWidth: 0.5))
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct SnoozeButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(red: 0.4, green: 0.65, blue: 0.95))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(red: 0.4, green: 0.65, blue: 0.95).opacity(0.1))
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}

struct DetailInfoRow: View {
    let label: String
    let value: String
    var isDarkMode: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isDarkMode ? Color.gray.opacity(0.6) : .gray)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(isDarkMode ? .white : .black)
                .lineLimit(2)

            Spacer()
        }
    }
}

// Simple wrapping flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            rowH = max(rowH, s.height); x += s.width + spacing
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowH = max(rowH, s.height); x += s.width + spacing
        }
    }
}

#Preview {
    DetailView(viewModel: OverlayViewModel())
}
