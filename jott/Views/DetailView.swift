import SwiftUI
import AppKit

// MARK: - Detail View

struct DetailView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ZStack {
            (viewModel.isDarkMode ? jottDetailDark : jottDetailLight)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                DetailHeader(viewModel: viewModel)

                Divider().opacity(0.1)

                ScrollView(showsIndicators: false) {
                    Group {
                        if let note = viewModel.selectedNote {
                            NoteDetailContent(note: note, viewModel: viewModel)
                                .id(note.id)
                        } else if let reminder = viewModel.selectedReminder {
                            ReminderDetailContent(reminder: reminder, viewModel: viewModel)
                        } else if let meeting = viewModel.selectedMeeting {
                            MeetingDetailContent(meeting: meeting, viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                }

                if let note = viewModel.selectedNote, !viewModel.isEditingNote {
                    NoteFooter(note: note, isDarkMode: viewModel.isDarkMode)
                }
            }
        }
    }
}

private let jottDetailDark  = Color(red: 0.13, green: 0.13, blue: 0.14)
private let jottDetailLight = Color(red: 0.96, green: 0.97, blue: 0.95)

// MARK: - Header

private struct DetailHeader: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var showInfo = false

    var accentGreen: Color {
        viewModel.isDarkMode
            ? Color(red: 0.55, green: 0.82, blue: 0.62)
            : Color(red: 0.28, green: 0.65, blue: 0.40)
    }

    var body: some View {
        HStack(spacing: 6) {
            // Back
            Button(action: {
                if let note = viewModel.selectedNote, viewModel.isEditingNote {
                    viewModel.saveEditedNote(note)
                }
                viewModel.selectedNote     = nil
                viewModel.selectedReminder = nil
                viewModel.selectedMeeting  = nil
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(accentGreen)
            }
            .buttonStyle(.plain)

            Spacer()

            if let note = viewModel.selectedNote {
                if viewModel.isEditingNote {
                    // Edit mode controls
                    Button(action: { viewModel.saveEditedNote(note) }) {
                        Label("Save", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.cancelEditingNote() }) {
                        Label("Cancel", systemImage: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    // View mode — compact icon strip
                    iconBtn("pin\(note.isPinned ? ".fill" : "")", color: note.isPinned ? .orange : .secondary) {
                        viewModel.togglePin(note)
                    }
                    iconBtn("doc.on.doc", color: .secondary) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(note.text, forType: .string)
                    }
                    iconBtn("arrow.up.right.square", color: .secondary) {
                        viewModel.openNoteInEditor(note)
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    // Info popover
                    Button(action: { showInfo.toggle() }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(showInfo ? accentGreen : .secondary.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showInfo, arrowEdge: .top) {
                        NoteInfoPopover(note: note, viewModel: viewModel)
                    }

                    iconBtn("trash", color: Color.red.opacity(0.55)) {
                        viewModel.deleteNote(note.id)
                        viewModel.selectedNote = nil
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            } else if let _ = viewModel.selectedReminder {
                typeBadge("REMINDER", color: Color(red: 0.55, green: 0.65, blue: 0.98))
            } else if let _ = viewModel.selectedMeeting {
                typeBadge("MEETING", color: Color(red: 0.98, green: 0.72, blue: 0.45))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func iconBtn(_ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
    }

    private func typeBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - Info Popover (dates, tags, links)

private struct NoteInfoPopover: View {
    let note: Note
    @ObservedObject var viewModel: OverlayViewModel
    @State private var showingLinkPicker = false

    var linkedNotes: [Note] { viewModel.linkedNotes(for: note) }
    var backlinks:   [Note] { viewModel.backlinks(for: note) }
    var wordCount: Int {
        note.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Metadata
            VStack(alignment: .leading, spacing: 6) {
                infoRow("Created",  value: formatDate(note.timestamp))
                infoRow("Modified", value: formatDate(note.modifiedAt))
                infoRow("Words",    value: "\(wordCount)  ·  \(max(1, wordCount / 200)) min read")
            }

            // Tags
            if !note.tags.isEmpty {
                Divider().opacity(0.15)
                popoverSection("TAGS") {
                    FlowLayout(spacing: 5) {
                        ForEach(note.tags, id: \.self) { tag in
                            Button {
                                viewModel.setTagFilter(tag)
                                viewModel.selectedNote = nil
                            } label: {
                                Text("#\(tag)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(red: 0.28, green: 0.65, blue: 0.40))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color(red: 0.28, green: 0.65, blue: 0.40).opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Linked notes
            Divider().opacity(0.15)
            popoverSection("LINKS") {
                if linkedNotes.isEmpty && backlinks.isEmpty {
                    Text("No linked notes. Type [[ to link.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(linkedNotes) { ln in
                            linkRow(ln, isBacklink: false) {
                                viewModel.unlinkNote(note.id, from: ln.id)
                            }
                        }
                        ForEach(backlinks) { bl in
                            linkRow(bl, isBacklink: true, onRemove: nil)
                        }
                    }
                }
                Button(action: { showingLinkPicker = true }) {
                    Label("Add link", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.28, green: 0.65, blue: 0.40))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(width: 240)
        .sheet(isPresented: $showingLinkPicker) {
            NoteLinkPickerView(
                viewModel: viewModel,
                sourceNoteId: note.id,
                alreadyLinked: note.linkedNoteIds
            )
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private func popoverSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.6)
            content()
        }
    }

    @ViewBuilder
    private func linkRow(_ n: Note, isBacklink: Bool, onRemove: (() -> Void)?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isBacklink ? "arrow.turn.up.left" : "link")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Button(action: { viewModel.selectedNote = n }) {
                Text(n.text.components(separatedBy: "\n").first ?? n.text)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            Spacer()
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Note footer (subtle one-liner)

private struct NoteFooter: View {
    let note: Note
    let isDarkMode: Bool

    private var wordCount: Int {
        note.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
    private var relativeDate: String {
        let interval = Date().timeIntervalSince(note.modifiedAt)
        if interval < 60       { return "just now" }
        if interval < 3600     { return "\(Int(interval / 60))m ago" }
        if interval < 86400    { return "\(Int(interval / 3600))h ago" }
        if interval < 604800   { return "\(Int(interval / 86400))d ago" }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return fmt.string(from: note.modifiedAt)
    }

    var body: some View {
        HStack {
            Text("Modified \(relativeDate)  ·  \(wordCount) word\(wordCount == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(isDarkMode ? Color.white.opacity(0.03) : Color.black.opacity(0.025))
    }
}

// MARK: - Note Detail Content

struct NoteDetailContent: View {
    let note: Note
    @ObservedObject var viewModel: OverlayViewModel
    @State private var showMarkdownPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isEditingNote {
                TextEditor(text: $viewModel.editingNoteText)
                    .font(.system(size: 15))
                    .foregroundColor(viewModel.isDarkMode ? .white : .black)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 200)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    Group {
                        if showMarkdownPreview,
                           let attrStr = try? AttributedString(markdown: note.text) {
                            Text(attrStr)
                                .font(.system(size: 15))
                                .lineSpacing(3)
                        } else {
                            Text(note.text)
                                .font(.system(size: 15, weight: .regular))
                                .lineSpacing(3)
                        }
                    }
                    .foregroundColor(viewModel.isDarkMode ? .white : Color(red: 0.1, green: 0.1, blue: 0.12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .onTapGesture { viewModel.startEditingNote(note) }

                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) { showMarkdownPreview.toggle() }
                    } label: {
                        Image(systemName: showMarkdownPreview ? "text.alignleft" : "doc.richtext")
                            .font(.system(size: 11))
                            .foregroundColor(showMarkdownPreview ? Color.accentColor.opacity(0.7) : .secondary.opacity(0.3))
                            .padding(4)
                            .background(showMarkdownPreview ? Color.accentColor.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { viewModel.startEditingNote(note) }
    }
}

// MARK: - Reminder Detail Content

struct ReminderDetailContent: View {
    let reminder: Reminder
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.4, green: 0.65, blue: 0.95))
                Text(reminder.text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(viewModel.isDarkMode ? .white : .black)
            }

            HStack(spacing: 6) {
                Text(reminder.isCompleted ? "Completed" : "Pending")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(reminder.isCompleted ? .green : Color(red: 0.4, green: 0.65, blue: 0.95))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((reminder.isCompleted ? Color.green : Color(red: 0.4, green: 0.65, blue: 0.95)).opacity(0.12))
                    .clipShape(Capsule())
                Text("Due \(formatDateTime(reminder.dueDate))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if !reminder.isCompleted {
                Divider().opacity(0.12)
                VStack(alignment: .leading, spacing: 6) {
                    Text("SNOOZE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.6)
                    HStack(spacing: 8) {
                        SnoozeButton(label: "30 min")       { viewModel.snoozeReminder(reminder, minutes: 30) }
                        SnoozeButton(label: "1 hour")       { viewModel.snoozeReminder(reminder, minutes: 60) }
                        SnoozeButton(label: "Tomorrow 9am") { viewModel.snoozeReminderToTomorrow(reminder) }
                    }
                }
            }
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Meeting Detail Content

struct MeetingDetailContent: View {
    let meeting: Meeting
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.98, green: 0.72, blue: 0.45))
                Text(meeting.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(viewModel.isDarkMode ? .white : .black)
            }

            HStack(spacing: 12) {
                Label(formatDateTime(meeting.startTime), systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Label("\(meeting.duration) min", systemImage: "timer")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if !meeting.participants.isEmpty {
                Divider().opacity(0.12)
                VStack(alignment: .leading, spacing: 6) {
                    Text("PARTICIPANTS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.6)
                    FlowLayout(spacing: 5) {
                        ForEach(meeting.participants, id: \.self) { p in
                            Label(p, systemImage: "person.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(red: 0.98, green: 0.72, blue: 0.45))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color(red: 0.98, green: 0.72, blue: 0.45).opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Snooze Button

struct SnoozeButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(red: 0.4, green: 0.65, blue: 0.95))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(red: 0.4, green: 0.65, blue: 0.95).opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail Info Row (kept for any remaining callers)

struct DetailInfoRow: View {
    let label: String
    let value: String
    var isDarkMode: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(isDarkMode ? .white : .primary)
            Spacer()
        }
    }
}

// MARK: - Linked Note Chip (kept for any remaining callers)

struct LinkedNoteChip: View {
    let note: Note
    let isDarkMode: Bool
    let onTap: () -> Void
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 5) {
                    Image(systemName: "link").font(.system(size: 10))
                    Text(note.text.components(separatedBy: "\n").first ?? note.text)
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 9))
                }
                .foregroundColor(isDarkMode ? .white : .primary)
            }
            .buttonStyle(.plain)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 9)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
    }
}

// MARK: - Flow Layout

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
