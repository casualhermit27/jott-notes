import SwiftUI
import AppKit

private enum LibraryFilter: Equatable {
    case none
    case pinned
    case tagged(String)
    case today
    case thisWeek
    case thisMonth
    case recentlyDeleted

    var label: String {
        switch self {
        case .none:          return "All"
        case .pinned:        return "Pinned"
        case .tagged(let t): return "#\(t)"
        case .today:         return "Today"
        case .thisWeek:      return "This week"
        case .thisMonth:     return "This month"
        case .recentlyDeleted: return "Recently Deleted"
        }
    }
    var isActive: Bool { self != .none }
}

private enum LibrarySelection: Equatable {
    case note(UUID)
    case reminder(UUID)
}

// MARK: - Design System

private struct JottDS {
    let isDark: Bool

    var canvas:      Color { isDark ? Color(red: 0.095, green: 0.095, blue: 0.100) : Color(red: 0.985, green: 0.983, blue: 0.976) }
    var surface:     Color { isDark ? Color(red: 0.132, green: 0.132, blue: 0.140) : Color(red: 0.998, green: 0.996, blue: 0.992) }
    var surfaceAlt:  Color { isDark ? Color(red: 0.155, green: 0.155, blue: 0.165) : Color(red: 0.952, green: 0.950, blue: 0.944) }
    var hairline:    Color { isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.07) }
    var hairlineMid: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.12) }
    var ink:         Color { isDark ? Color(white: 0.95) : Color(red: 0.14, green: 0.14, blue: 0.15) }
    var inkMute:     Color { isDark ? Color(white: 0.68) : Color(red: 0.36, green: 0.36, blue: 0.39) }
    var inkFaint:    Color { isDark ? Color(white: 0.50) : Color(red: 0.52, green: 0.52, blue: 0.55) }
    var inkFaintest: Color { isDark ? Color(white: 0.38) : Color(red: 0.70, green: 0.70, blue: 0.73) }
    var accent:      Color { isDark ? Color(red: 0.58, green: 0.48, blue: 0.88) : Color(red: 0.42, green: 0.30, blue: 0.76) }
    var accentSoft:  Color { accent.opacity(isDark ? 0.14 : 0.10) }
    var accentRing:  Color { accent.opacity(isDark ? 0.52 : 0.42) }
}

struct LibraryView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject private var noteStore = NoteStore.shared
    @Namespace private var gridCardNamespace
    @State private var searchText: String = ""
    @State private var selectedItem: LibrarySelection?
    @State private var selectedNoteIDs: Set<UUID> = []
    @State private var selectionAnchorNoteID: UUID?
    @State private var isDragSelectingNotes = false
    @State private var isDetailExpanded: Bool = false
    @State private var showDeleteConfirm = false
    @State private var activeFilter: LibraryFilter = .none
    /// Debounced search results — updated async, never on every keystroke.
    @State private var searchResults: [SearchResult] = []
    // Folder navigation stack (root folders when empty, deeper when navigated in)
    @State private var folderStack: [UUID] = []
    private var activeFolderID: UUID? { folderStack.last }
    @State private var renamingFolderID: UUID? = nil
    @State private var renameFolderName: String = ""
    @State private var showRenameFolderSheet = false
    private var isDarkMode: Bool {
        viewModel.isDarkMode
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private var availableTags: [String] {
        Array(Set(viewModel.getAllNotes().flatMap { $0.tags })).sorted()
    }

    private var isRecentlyDeleted: Bool {
        activeFilter == .recentlyDeleted
    }

    private var filteredNotes: [Note] {
        if isRecentlyDeleted {
            return NoteStore.shared.deletedNotes().filter { $0.parentId == nil }
        }
        if isSearching {
            return searchResults.compactMap { r in r.isSubnote ? nil : r.note }
        }
        var base = viewModel.getAllNotes().filter { $0.parentId == nil }
        // Folder drill-down filter
        if let fid = activeFolderID {
            base = base.filter { $0.folderId == fid }
        }
        switch activeFilter {
        case .none:          return base
        case .pinned:        return base.filter { $0.isPinned }
        case .tagged(let t): return base.filter { $0.tags.contains(t) }
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            return base.filter { $0.modifiedAt >= start }
        case .thisWeek:
            let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return base.filter { $0.modifiedAt >= start }
        case .thisMonth:
            let start = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            return base.filter { $0.modifiedAt >= start }
        case .recentlyDeleted:
            return base
        }
    }

    private var visibleNotes: [Note] { filteredNotes }

    private var filteredItemCount: Int {
        isSearching ? searchResults.count : visibleNotes.count
    }

    private var sortedVisibleNotes: [Note] {
        if isSearching {
            return filteredNotes  // already ranked by SearchEngine
        }
        return visibleNotes.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private var selectedNote: Note? {
        guard case .note(let id) = selectedItem else { return nil }
        return isRecentlyDeleted
            ? NoteStore.shared.deletedNotes().first(where: { $0.id == id })
            : NoteStore.shared.allNotes().first(where: { $0.id == id })
    }

    private var selectionSyncSignature: String {
        let noteSignature = filteredNotes.map { $0.id.uuidString }.joined(separator: ",")
        return [searchText, activeFolderID?.uuidString ?? "", noteSignature]
            .joined(separator: "|")
    }

    var body: some View {
        libraryScaffold
    }

    private var libraryScaffold: AnyView {
        AnyView(
            VStack(spacing: 0) {
                LibraryTopBar(
                    searchText: $searchText,
                    activeFilter: $activeFilter,
                    visibleCount: filteredItemCount,
                    selectedCount: selectedNoteIDs.count,
                    isDarkMode: isDarkMode,
                    selectedNote: selectedNote,
                    availableTags: availableTags,
                    destructiveActionLabel: isRecentlyDeleted ? "Delete Forever" : "Delete",
                    onDismissDetail: { clearSelection() },
                    onDeleteSelected: { showDeleteConfirm = true }
                )

                Divider().opacity(isDarkMode ? 0.16 : 0.10)

                // Folder strip — always visible unless searching or viewing trash
                if !isSearching && !isRecentlyDeleted {
                    FolderStrip(
                        noteStore: noteStore,
                        folderStack: folderStack,
                        isDark: isDarkMode,
                        onPop: {
                            withAnimation(JottMotion.content) {
                                folderStack = Array(folderStack.dropLast())
                            }
                        },
                        onPush: { id in
                            withAnimation(JottMotion.content) { folderStack.append(id) }
                        },
                        onAddFolder: nil,
                        onRenameFolder: { folder in
                            renameFolderName = folder.name
                            renamingFolderID = folder.id
                            showRenameFolderSheet = true
                        }
                    )
                    Divider().opacity(isDarkMode ? 0.10 : 0.07)
                }

                ZStack(alignment: .bottomTrailing) {
                    primaryPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(isDetailExpanded ? 0 : 1)

                    // Floating new note button
                    if selectedNote == nil && !isRecentlyDeleted {
                        Button {
                            let newNote = Note(blocks: [Block(type: .paragraph, spans: [TextSpan("")])],
                                              folderId: activeFolderID)
                            NoteStore.shared.upsertNote(newNote)
                            viewModel.selectedNote = NoteStore.shared.note(for: newNote.id) ?? newNote
                            viewModel.startEditingNote(viewModel.selectedNote ?? newNote)
                            withAnimation(JottMotion.content) {
                                selectedItem = .note(newNote.id)
                                selectedNoteIDs = [newNote.id]
                                selectionAnchorNoteID = newNote.id
                            }
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 46, height: 46)
                                .background(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(JottDS(isDark: isDarkMode).accent)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                        .padding(.bottom, 14)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }

                    if let note = selectedNote {
                        LibraryNoteDetailPanel(
                            note: note,
                            viewModel: viewModel,
                            isDark: isDarkMode,
                            isExpanded: $isDetailExpanded,
                            onClose: {
                                isDetailExpanded = false
                                clearSelection()
                            }
                        )
                        .id(note.id)
                        .transition(.opacity)
                        .frame(maxWidth: isDetailExpanded ? .infinity : 360, maxHeight: .infinity)
                        .animation(.easeInOut(duration: 0.16), value: note.id)
                        .background(isDarkMode
                            ? Color(red: 0.082, green: 0.082, blue: 0.090)
                            : Color(red: 0.984, green: 0.984, blue: 0.990)
                        )
                        .frame(maxWidth: isDetailExpanded ? .infinity : 361)
                        .overlay(alignment: .leading) {
                            Divider()
                                .opacity(isDetailExpanded ? 0 : (isDarkMode ? 0.14 : 0.09))
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
                .animation(.spring(response: 0.40, dampingFraction: 0.84), value: isDetailExpanded)
            }
            .background(JottDS(isDark: isDarkMode).canvas)
            .colorScheme(isDarkMode ? .dark : .light)
            .jottAppTypography()
            .task(id: selectionSyncSignature) {
                syncSelection()
            }
            .onChange(of: viewModel.isVisible) { _, visible in
                if visible { searchText = "" }
            }
            .onChange(of: viewModel.navigationStack) { _, stack in
                if let top = stack.last {
                    withAnimation(JottMotion.content) { selectedItem = .note(top.id) }
                }
            }
            // Debounced search — 180ms wait, then run off main thread
            .task(id: searchText) {
                guard !searchText.isEmpty else {
                    searchResults = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                let q = searchText
                let results = await Task.detached(priority: .userInitiated) {
                    SearchEngine.shared.search(query: q, store: NoteStore.shared)
                }.value
                guard !Task.isCancelled else { return }
                searchResults = results
            }
            .background { libraryScaffoldNotificationListener }
            // Delete shortcuts — plain Delete or Cmd+Delete
            .background {
                Group {
                    Button("") { if !selectedNoteIDs.isEmpty { showDeleteConfirm = true } }
                        .keyboardShortcut(.delete, modifiers: [])
                    Button("") { if !selectedNoteIDs.isEmpty { showDeleteConfirm = true } }
                        .keyboardShortcut(.delete, modifiers: .command)
                }
                .hidden()
            }
            // Delete confirmation overlay
            .overlay {
                if showDeleteConfirm {
                    DeleteConfirmOverlay(
                        count: selectedNoteIDs.count,
                        isPermanent: isRecentlyDeleted,
                        isDark: isDarkMode,
                        onDelete: { deleteSelectedNotes() },
                        onCancel: { showDeleteConfirm = false }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: showDeleteConfirm)
            .sheet(isPresented: $showRenameFolderSheet) {
                RenameFolderSheet(
                    folderName: $renameFolderName,
                    isDark: isDarkMode,
                    onRename: { name in
                        if let id = renamingFolderID {
                            NoteStore.shared.renameFolder(id, to: name)
                        }
                        showRenameFolderSheet = false
                        renamingFolderID = nil
                    },
                    onCancel: {
                        showRenameFolderSheet = false
                        renamingFolderID = nil
                    }
                )
            }
        )
    }

    private var primaryPane: some View {
        Group {
            if isSearching {
                SearchResultsView(
                    results: searchResults,
                    query: searchText,
                    isDark: isDarkMode,
                    selectedNote: selectedNote,
                    matchedFolders: noteStore.folders.filter {
                        $0.name.localizedCaseInsensitiveContains(searchText)
                    },
                    onSelect: { note in select(note: note) },
                    onSelectFolder: { id in
                        searchText = ""
                        withAnimation(JottMotion.content) { folderStack = [id] }
                    }
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            } else {
                libraryGridView
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isSearching)
    }

    private var libraryGridView: some View {
        let ds = JottDS(isDark: isDarkMode)
        let notes = sortedVisibleNotes
        let pinnedNotes = notes.filter { $0.isPinned }
        let regularNotes = notes.filter { !$0.isPinned }

        return GeometryReader { proxy in
            let spacing: CGFloat = 16
            let targetWidth: CGFloat = 260
            let usable = max(proxy.size.width, targetWidth)
            let cols = max(1, Int((usable + spacing) / (targetWidth + spacing)))
            // Pinned notes: max 2 columns so each card is noticeably wider
            let pinnedCols = min(2, cols)
            let columns       = Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: cols)
            let pinnedColumns = Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: pinnedCols)

            ScrollView(showsIndicators: false) {
                if notes.isEmpty {
                    LibraryEmptyState(
                        title: isRecentlyDeleted
                            ? "Recently Deleted is empty"
                            : (activeFolderID != nil ? "Nothing in this folder" : "No notes yet"),
                        message: isRecentlyDeleted
                            ? "Deleted notes stay here until you delete them forever."
                            : (activeFolderID != nil
                            ? "Right-click any note and choose Move to Folder."
                            : "Capture something and it will land here.")
                    )
                    .frame(height: max(proxy.size.height - 32, 200))
                } else {
                    VStack(alignment: .leading, spacing: spacing) {
                        // ── Pinned section (wider, taller cards) ──
                        if !pinnedNotes.isEmpty {
                            LazyVGrid(columns: pinnedColumns, alignment: .leading, spacing: spacing) {
                                ForEach(pinnedNotes, id: \.id) { note in
                                    LibraryMinimalNoteCard(
                                        note: note,
                                        estimatedHeight: pinnedCardEstimatedHeight(for: note),
                                        isSelected: selectedNoteIDs.contains(note.id),
                                        isDarkMode: isDarkMode,
                                        subnoteCount: viewModel.subnoteCount(of: note.id),
                                        animationNamespace: gridCardNamespace,
                                        isDragSelecting: $isDragSelectingNotes,
                                        onActivate: { modifiers in select(note: note, modifiers: modifiers) },
                                        onDragSelect: { dragSelect(note: note) },
                                        viewModel: viewModel
                                    )
                                    .contextMenu { noteContextMenu(for: note) }
                                }
                            }
                            if !regularNotes.isEmpty {
                                Rectangle().fill(ds.hairline).frame(height: 1)
                            }
                        }
                        // ── Regular notes ──
                        if !regularNotes.isEmpty {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                                ForEach(regularNotes, id: \.id) { note in
                                    LibraryMinimalNoteCard(
                                        note: note,
                                        estimatedHeight: gridCardEstimatedHeight(for: note),
                                        isSelected: selectedNoteIDs.contains(note.id),
                                        isDarkMode: isDarkMode,
                                        subnoteCount: viewModel.subnoteCount(of: note.id),
                                        animationNamespace: gridCardNamespace,
                                        isDragSelecting: $isDragSelectingNotes,
                                        onActivate: { modifiers in select(note: note, modifiers: modifiers) },
                                        onDragSelect: { dragSelect(note: note) },
                                        viewModel: viewModel
                                    )
                                    .contextMenu { noteContextMenu(for: note) }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func noteContextMenu(for note: Note) -> some View {
        if isRecentlyDeleted {
            Button {
                NoteStore.shared.restoreNote(note.id)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }

            Divider()

            Button(role: .destructive) {
                selectedNoteIDs = [note.id]
                showDeleteConfirm = true
            } label: {
                Label("Delete Forever", systemImage: "trash.slash")
            }
        } else {
        Button("Edit Note") {
            select(note: note)
        }

        Divider()

        Menu("Move to Folder") {
            if note.folderId != nil {
                Button("Remove from Folder") {
                    NoteStore.shared.moveNote(note.id, toFolder: nil)
                }
                Divider()
            }
            ForEach(noteStore.folders) { folder in
                Button {
                    NoteStore.shared.moveNote(note.id, toFolder: folder.id)
                } label: {
                    HStack {
                        Image(systemName: "folder.fill")
                        Text(folder.name)
                        if note.folderId == folder.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if noteStore.folders.isEmpty {
                Text("No folders yet")
                    .foregroundColor(.secondary)
            }
        }

        Button(note.isPinned ? "Unpin" : "Pin") {
            NoteStore.shared.togglePin(note.id)
        }

        Button {
            viewModel.focusedNote = note
        } label: {
            Label("Pin to Focus", systemImage: "pin.fill")
        }

        Divider()

        Button(role: .destructive) {
            selectedNoteIDs = [note.id]
            showDeleteConfirm = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        }
    }

    private var libraryScaffoldNotificationListener: some View {
        Color.clear.frame(width: 0, height: 0)
    }

    private func pinnedCardEstimatedHeight(for note: Note) -> CGFloat {
        let nonEmptyLines = note.blocks
            .map { $0.plainText.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let characterCount = nonEmptyLines.joined(separator: " ").count
        let hasImage = note.blocks.contains { $0.type == .image && !($0.imageURL ?? "").isEmpty }
        let subnoteCount = viewModel.subnoteCount(of: note.id)
        let densityScore = min(nonEmptyLines.count, 5) + min(characterCount / 80, 3) + (hasImage ? 2 : 0) + min(subnoteCount, 2)

        switch densityScore {
        case ...2: return 340
        case 3...4: return 380
        case 5...6: return 420
        default: return 460
        }
    }

    private func gridCardEstimatedHeight(for note: Note) -> CGFloat {
        let nonEmptyLines = note.blocks
            .map { $0.plainText.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let characterCount = nonEmptyLines.joined(separator: " ").count
        let hasImage = note.blocks.contains { $0.type == .image && !($0.imageURL ?? "").isEmpty }
        let subnoteCount = viewModel.subnoteCount(of: note.id)
        let densityScore = min(nonEmptyLines.count, 5) + min(characterCount / 80, 3) + (hasImage ? 2 : 0) + min(subnoteCount, 2)

        switch densityScore {
        case ...2: return 260
        case 3...4: return 300
        case 5...6: return 340
        default: return 380
        }
    }


    private func select(note: Note, modifiers: NSEvent.ModifierFlags = []) {
        // Commit any in-progress note edit before switching notes
        if viewModel.isEditingNote {
            if let current = selectedNote {
                viewModel.saveEditedNote(current)
            } else {
                viewModel.cancelEditingNote()
            }
        }

        let relevantModifiers = modifiers.intersection([.shift, .command, .control])

        if relevantModifiers.contains(.shift) {
            applyRangeSelection(to: note.id)
            // Multi-select — close sidebar
            withAnimation(JottMotion.content) { selectedItem = nil }
            return
        }

        if relevantModifiers.contains(.command) || relevantModifiers.contains(.control) {
            if selectedNoteIDs.contains(note.id) {
                selectedNoteIDs.remove(note.id)
                // If back to single selection, reopen sidebar for the remaining note
                if selectedNoteIDs.count == 1, let remaining = selectedNoteIDs.first {
                    withAnimation(JottMotion.content) { selectedItem = .note(remaining) }
                } else {
                    withAnimation(JottMotion.content) { selectedItem = nil }
                }
            } else {
                selectedNoteIDs.insert(note.id)
                selectionAnchorNoteID = note.id
                // Multi-select — close sidebar
                withAnimation(JottMotion.content) { selectedItem = nil }
            }
            return
        }

        viewModel.navigationStack.removeAll()
        viewModel.selectedNote = note
        withAnimation(JottMotion.content) {
            selectedItem = .note(note.id)
            selectedNoteIDs = [note.id]
            selectionAnchorNoteID = note.id
        }
    }

    private func dragSelect(note: Note) {
        guard isDragSelectingNotes else { return }
        if !selectedNoteIDs.contains(note.id) {
            selectedNoteIDs.insert(note.id)
            selectedItem = .note(note.id)
            selectionAnchorNoteID = selectionAnchorNoteID ?? note.id
        }
    }

    private func applyRangeSelection(to targetID: UUID) {
        let noteIDs = visibleNotes.map(\.id)
        guard let targetIndex = noteIDs.firstIndex(of: targetID) else {
            selectedNoteIDs = [targetID]
            selectionAnchorNoteID = targetID
            return
        }

        let anchorID = selectionAnchorNoteID ?? selectedNote?.id ?? targetID
        let anchorIndex = noteIDs.firstIndex(of: anchorID) ?? targetIndex
        let lower = min(anchorIndex, targetIndex)
        let upper = max(anchorIndex, targetIndex)
        selectedNoteIDs = Set(noteIDs[lower...upper])
        selectionAnchorNoteID = anchorID
    }

    private func clearSelection() {
        if viewModel.isEditingNote {
            if let current = selectedNote { viewModel.saveEditedNote(current) }
            else { viewModel.cancelEditingNote() }
        }
        viewModel.navigationStack.removeAll()
        viewModel.selectedNote = nil
        withAnimation(JottMotion.content) {
            selectedItem = nil
            selectedNoteIDs.removeAll()
            selectionAnchorNoteID = nil
            isDetailExpanded = false
        }
    }

    private func deleteSelectedNotes() {
        let ids = selectedNoteIDs
        let permanently = isRecentlyDeleted
        withAnimation(JottMotion.content) {
            showDeleteConfirm = false
            selectedItem = nil
            selectedNoteIDs.removeAll()
            selectionAnchorNoteID = nil
        }
        for id in ids {
            if permanently {
                viewModel.permanentlyDeleteNote(id)
            } else {
                viewModel.deleteNote(id)
            }
        }
    }

    private func syncSelection() {
        let availableNoteIDs = Set(visibleNotes.map(\.id))

        switch selectedItem {
        case .note(let id) where !availableNoteIDs.contains(id):
            selectedItem = nil
            selectedNoteIDs.formIntersection(availableNoteIDs)
        case .reminder:
            selectedItem = nil
        default:
            break
        }
    }

}

private struct LibraryMinimalNoteCard: View {
    let note: Note
    let estimatedHeight: CGFloat
    let isSelected: Bool
    let isDarkMode: Bool
    var subnoteCount: Int = 0
    let animationNamespace: Namespace.ID
    @Binding var isDragSelecting: Bool
    let onActivate: (NSEvent.ModifierFlags) -> Void
    var onDoubleActivate: (() -> Void)? = nil
    let onDragSelect: () -> Void
    @ObservedObject var viewModel: OverlayViewModel
    @State private var hovered = false
    @State private var thumbnail: NSImage?
    @State private var showSubnotes: Bool = false

    private var displayBlocks: [Block] {
        jottDisplayBlocks(from: note.blocks)
    }

    private var subnotePreviews: [String] {
        NoteStore.shared.subnotes(of: note.id)
            .prefix(3)
            .compactMap { sub in
                sub.blocks.lazy
                    .compactMap(textTitle(for:))
                    .first
            }
    }

    private var title: String {
        if let textTitle = displayBlocks.lazy.compactMap(textTitle(for:)).first {
            return textTitle
        }
        if let table = displayBlocks.first(where: { $0.type == .table }) {
            let columns = max(table.tableHeaders.count, table.tableRows.first?.count ?? 0)
            return columns > 0 ? "Table · \(columns) column\(columns == 1 ? "" : "s")" : "Table"
        }
        return "Untitled"
    }

    private var previewLines: [String] {
        let cleaned = displayBlocks.flatMap { previewLines(for: $0) }

        guard !cleaned.isEmpty else { return [] }
        return Array(cleaned.dropFirst().prefix(thumbnail == nil ? 3 : 2))
    }

    private var previewText: String? {
        let text = previewLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private var metadataLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: note.modifiedAt).uppercased()
    }

    private var relativeTimeLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: note.modifiedAt, relativeTo: Date())
    }

    private var firstImagePath: String? {
        if let imageBlock = displayBlocks.first(where: { $0.type == .image }),
           let imageURL = imageBlock.imageURL,
           !imageURL.isEmpty {
            return imageURL
        }
        return nil
    }

    private func textTitle(for block: Block) -> String? {
        switch block.type {
        case .paragraph, .heading, .bulletItem, .numberedItem, .taskItem, .quote:
            let value = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        default:
            return nil
        }
    }

    private func previewLines(for block: Block) -> [String] {
        switch block.type {
        case .paragraph, .heading, .bulletItem, .numberedItem, .taskItem, .quote:
            let value = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? [] : [value]
        case .table:
            let columns = max(block.tableHeaders.count, block.tableRows.first?.count ?? 0)
            let rows = block.tableRows.count
            guard columns > 0 else { return ["Table"] }
            return ["\(columns) column\(columns == 1 ? "" : "s") · \(rows) row\(rows == 1 ? "" : "s")"]
        default:
            return []
        }
    }

    @ViewBuilder
    private var subnoteButtonsOverlay: some View {
        let ds = JottDS(isDark: isDarkMode)
        if subnoteCount > 0 {
            Button {
                withAnimation(.easeInOut(duration: 0.20)) {
                    showSubnotes.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 9, weight: .semibold))
                    Text("\(subnoteCount)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    Image(systemName: showSubnotes ? "chevron.down" : "chevron.up")
                        .font(.system(size: 7, weight: .semibold))
                }
                .foregroundColor(ds.accent.opacity(isDarkMode ? 0.85 : 0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(ds.accentSoft.opacity(isDarkMode ? 0.88 : 0.92)))
                .overlay(Capsule(style: .continuous).strokeBorder(ds.accent.opacity(showSubnotes ? 0.45 : (isDarkMode ? 0.25 : 0.12)), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .padding(.bottom, 10)
        }
    }

    var body: some View {
        let ds = JottDS(isDark: isDarkMode)

        ZStack(alignment: .top) {
            // ── Stacked border layers for subnotes ──
            if subnoteCount > 0 {
                // Back layer
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDarkMode ? Color(white: 0.06) : Color(white: 0.96))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isDarkMode ? Color(white: 0.22) : Color(white: 0.82), lineWidth: 1))
                    .padding(.horizontal, 10)
                    .offset(y: 7)

                // Middle layer
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDarkMode ? Color(white: 0.07) : Color(white: 0.97))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isDarkMode ? Color(white: 0.25) : Color(white: 0.84), lineWidth: 1))
                    .padding(.horizontal, 5)
                    .offset(y: 3.5)
            }

            // ── Main card ──
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(metadataLabel)
                        .font(.system(size: 10.5, design: .monospaced).weight(.medium))
                        .foregroundColor(ds.inkFaintest)
                        .tracking(0.4)
                    Spacer()
                    if note.isPinned {
                        Text("PINNED")
                            .font(.system(size: 9, design: .monospaced).weight(.medium))
                            .foregroundColor(ds.accent.opacity(0.45))
                            .tracking(0.6)
                            .padding(.trailing, 6)
                    }
                    Text(relativeTimeLabel)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(ds.inkFaintest)
                        .tracking(0.4)
                }

                Spacer().frame(height: 10)

                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundColor(ds.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(1)

                if let previewText {
                    Spacer().frame(height: 7)
                    Text(previewText)
                        .font(.system(size: 12))
                        .foregroundColor(ds.inkMute)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(2)
                }

                if let thumbnail {
                    Spacer().frame(height: 10)
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ds.hairline, lineWidth: 1))
                }

                // ── Subnote stack preview (toggled by pill) ──
                if showSubnotes && !subnotePreviews.isEmpty {
                    Spacer(minLength: 12)
                    Divider().opacity(0.3)
                    Spacer().frame(height: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(subnotePreviews.enumerated()), id: \.offset) { i, preview in
                            HStack(alignment: .center, spacing: 6) {
                                Text("•")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(ds.accent.opacity(0.50))
                                Text(preview)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(ds.inkFaint)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    Spacer().frame(height: 6)
                }

                Spacer(minLength: subnoteCount > 0 ? 36 : 10)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hovered ? ds.surfaceAlt : ds.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isSelected ? ds.accentRing : ds.hairline, lineWidth: isSelected ? 1.5 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        hovered && !isSelected ? ds.accent.opacity(isDarkMode ? 0.18 : 0.14) : .clear,
                        lineWidth: hovered && !isSelected ? 1 : 0
                    )
            )
            // ── Folder name (bottom-right) ──
            .overlay(alignment: .bottomTrailing) {
                if let fid = note.folderId,
                   let folder = NoteStore.shared.folders.first(where: { $0.id == fid }),
                   subnoteCount == 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                            .foregroundColor(folder.displayColor.opacity(0.70))
                        Text(folder.name)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(ds.inkFaintest.opacity(0.65))
                            .lineLimit(1)
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                }
            }
            // ── Subnote pill + open button ──
            .overlay(alignment: .bottomTrailing) {
                subnoteButtonsOverlay
            }
            .shadow(
                color: isSelected ? ds.accent.opacity(isDarkMode ? 0.22 : 0.14)
                     : hovered   ? ds.accent.opacity(isDarkMode ? 0.08 : 0.05) : .clear,
                radius: isSelected ? 8 : hovered ? 4 : 0, x: 0, y: 0
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .matchedGeometryEffect(
                id: "library-grid-card-\(note.id.uuidString)",
                in: animationNamespace,
                properties: .frame,
                anchor: .topLeading
            )
            .onTapGesture(count: 2) { if NSEvent.modifierFlags.intersection([.shift, .command, .control]).isEmpty { onDoubleActivate?() } }
            .onTapGesture(count: 1) { onActivate(NSEvent.modifierFlags) }
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { _ in if !isDragSelecting { isDragSelecting = true; onDragSelect() } }
                    .onEnded { _ in isDragSelecting = false }
            )
            .animation(JottMotion.micro, value: hovered)
            .animation(JottMotion.micro, value: isSelected)
            .onHover { hovering in
                withAnimation(JottMotion.micro) { hovered = hovering }
                if hovering && isDragSelecting { onDragSelect() }
            }
            .task(id: note.id) {
                guard let path = firstImagePath else { thumbnail = nil; return }
                let url = NoteStore.shared.attachmentURL(for: path)
                thumbnail = NSImage(contentsOf: url)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .padding(.bottom, subnoteCount > 0 ? 10 : 2)
    }

}

// MARK: - Library Grid Expanded Card

// MARK: - Library Note Detail Panel

private struct LibraryNoteDetailPanel: View {
    let note: Note
    @ObservedObject var viewModel: OverlayViewModel
    let isDark: Bool
    @Binding var isExpanded: Bool
    let onClose: () -> Void

    @State private var showingSubnoteInput: Bool = false
    @State private var newSubnoteText: String = ""
    @State private var subnoteEditorHeight: CGFloat = SubnoteTextEditor.minHeight
    @State private var subnoteAutoSaveTask: Task<Void, Never>? = nil

    // Pastel squish button color
    private var squishColor: Color {
        isDark
            ? Color(red: 0.58, green: 0.50, blue: 0.92)   // soft lavender
            : Color(red: 0.62, green: 0.52, blue: 0.96)
    }


    var body: some View {
        let ds = JottDS(isDark: isDark)
        let hasSubnotes = !viewModel.subnotes(of: note.id).isEmpty

        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // ── Header ──
                HStack(spacing: 8) {
                    // Back button when inside a subnote
                    if viewModel.navigationStack.count > 1 {
                        Button(action: {
                            viewModel.popNavigation()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 10, weight: .semibold))
                                let parentNote = viewModel.navigationStack.dropLast().last
                                let parentTitle = parentNote?.text
                                    .components(separatedBy: "\n")
                                    .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Back"
                                Text(parentTitle ?? "Back")
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(squishColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(squishColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Mono meta: date · relative time
                        Text("\(formattedDate)  ·  \(relativeTimeLabel)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(ds.inkFaint)
                            .tracking(0.3)
                    }

                    Spacer()

                    // Edit / Done toggle
                    Button {
                        if viewModel.isEditingNote {
                            viewModel.saveEditedNote(note)
                        } else {
                            viewModel.startEditingNote(note)
                        }
                    } label: {
                        Text(viewModel.isEditingNote ? "Done" : "Edit")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(viewModel.isEditingNote ? squishColor : ds.inkFaint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(viewModel.isEditingNote ? squishColor.opacity(0.14) : (isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
                            )
                    }
                    .buttonStyle(.plain)

                    // Open in editor
                    Button {
                        viewModel.openNoteInEditor(note)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ds.inkFaint)
                            .frame(width: 26, height: 26)
                            .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Open .md file in default editor")

                    // Expand
                    Button {
                        withAnimation(JottMotion.content) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ds.inkFaint)
                            .frame(width: 26, height: 26)
                            .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    // Close
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ds.inkFaint)
                            .frame(width: 26, height: 26)
                            .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Rectangle().fill(ds.hairline).frame(height: 1)

                // ── Scrollable content ──
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        NoteDetailContent(note: note, viewModel: viewModel)

                        // Inline subnote input (shown after tapping the button)
                        if showingSubnoteInput {
                            subnoteInputRow
                                .padding(.top, 12)
                        }

                        Spacer().frame(height: viewModel.isEditingNote ? 8 : 72)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                }

                // ── Format toolbar (editing only) ──
                if viewModel.isEditingNote {
                    Rectangle().fill(ds.hairline).frame(height: 1)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LibraryEditFormatBar(blocks: Binding(
                            get: { viewModel.editingNoteBlocks },
                            set: { viewModel.editingNoteBlocks = $0 }
                        ))
                        .padding(.horizontal, 14)
                    }
                    .frame(height: 44)
                }
            }

            // ── Subnote button ──
            let subnoteButtonVisible = !showingSubnoteInput && !viewModel.isEditingNote
            Button {
                withAnimation(JottMotion.content) { showingSubnoteInput = true }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle").font(.system(size: 12, weight: .semibold))
                    Text("New Subnote").font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(squishColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(squishColor.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(squishColor.opacity(0.22), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 18)
            .opacity(subnoteButtonVisible ? 1 : 0)
            .scaleEffect(subnoteButtonVisible ? 1 : 0.88)
            .animation(JottMotion.micro, value: showingSubnoteInput)
            .animation(JottMotion.micro, value: viewModel.isEditingNote)
        }
        .background(
            isDark
                ? Color(red: 0.082, green: 0.082, blue: 0.090)
                : Color(red: 0.984, green: 0.984, blue: 0.990)
        )
        .onChange(of: note.id) { _, _ in
            resetSubnoteComposer()
        }
    }

    // ── Subnote quick-add row ──
    // Enter/Shift+Enter → new line. Escape or focus loss → save & close.
    private var subnoteInputRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack(alignment: .topLeading) {
                SubnoteTextEditor(
                    text: $newSubnoteText,
                    height: $subnoteEditorHeight,
                    isDark: isDark,
                    onFocusChange: { focused in
                        if !focused { commitSubnote() }
                    },
                    onDismiss: { commitSubnote() }
                )
                .frame(height: subnoteEditorHeight)

                if newSubnoteText.isEmpty {
                    Text("Add subnote…")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.28))
                        .allowsHitTesting(false)
                        .padding(.top, 1)
                }
            }

            Button {
                resetSubnoteComposer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.35))
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(squishColor.opacity(0.38), lineWidth: 1)
                )
        )
        .onAppear {
            // Restore any draft already in progress for this note
            if viewModel.subnoteSessionParentId == note.id,
               !viewModel.subnoteSessionText.isEmpty {
                newSubnoteText = viewModel.subnoteSessionText
            }
            subnoteEditorHeight = SubnoteTextEditor.minHeight
        }
        .onChange(of: newSubnoteText) { _, value in
            scheduleSubnoteAutoSave(value)
        }
    }

    private func scheduleSubnoteAutoSave(_ value: String) {
        subnoteAutoSaveTask?.cancel()
        subnoteAutoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    viewModel.autoSaveSubnoteDraft(parentId: note.id, text: trimmed)
                }
            }
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: note.modifiedAt).uppercased()
    }

    private var relativeTimeLabel: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: note.modifiedAt, relativeTo: Date())
    }

    private func commitSubnote() {
        subnoteAutoSaveTask?.cancel()
        let text = newSubnoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            viewModel.autoSaveSubnoteDraft(parentId: note.id, text: text)
            viewModel.commitSubnoteDraft()
        } else {
            viewModel.discardSubnoteDraft(parentId: note.id)
        }
        resetSubnoteComposer()
    }

    private func resetSubnoteComposer() {
        subnoteAutoSaveTask?.cancel()
        newSubnoteText = ""
        subnoteEditorHeight = SubnoteTextEditor.minHeight
        withAnimation(JottMotion.content) {
            showingSubnoteInput = false
        }
    }
}

// MARK: - In-Place Expanded Card (grid mode)

private struct LibraryInPlaceDetailCard: View {
    let note: Note
    @ObservedObject var viewModel: OverlayViewModel
    let isDarkMode: Bool
    let ds: JottDS
    let animationNamespace: Namespace.ID
    var isFullScreen: Bool = false
    let onClose: () -> Void
    var onExpand: (() -> Void)? = nil

    @State private var showingSubnoteInput: Bool = false
    @State private var newSubnoteText: String = ""
    @State private var subnoteEditorHeight: CGFloat = SubnoteTextEditor.minHeight
    @State private var subnoteAutoSaveTask: Task<Void, Never>? = nil

    private var formattedDate: String {
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return f.string(from: note.modifiedAt).uppercased()
    }
    private var relativeTime: String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: note.modifiedAt, relativeTo: Date())
    }
    private var squishColor: Color {
        isDarkMode
            ? Color(red: 0.58, green: 0.50, blue: 0.92)
            : Color(red: 0.62, green: 0.52, blue: 0.96)
    }

    private func commitSubnote() {
        subnoteAutoSaveTask?.cancel()
        let text = newSubnoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            viewModel.autoSaveSubnoteDraft(parentId: note.id, text: text)
            viewModel.commitSubnoteDraft()
        } else {
            viewModel.discardSubnoteDraft(parentId: note.id)
        }
        newSubnoteText = ""
        subnoteEditorHeight = SubnoteTextEditor.minHeight
        withAnimation(JottMotion.content) { showingSubnoteInput = false }
    }

    var body: some View {
        let hasSubnotes = !viewModel.subnotes(of: note.id).isEmpty

        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Text("\(formattedDate)  ·  \(relativeTime)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(ds.inkFaint)
                        .tracking(0.3)
                    Spacer()
                    if let onExpand, !isFullScreen {
                        Button(action: onExpand) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(ds.inkFaint)
                                .frame(width: 24, height: 24)
                                .background(isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ds.inkFaint)
                            .frame(width: 24, height: 24)
                            .background(isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Rectangle().fill(ds.hairline).frame(height: 1)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        NoteDetailContent(note: note, viewModel: viewModel)

                        if showingSubnoteInput {
                            ZStack(alignment: .topLeading) {
                                SubnoteTextEditor(
                                    text: $newSubnoteText,
                                    height: $subnoteEditorHeight,
                                    isDark: isDarkMode,
                                    onFocusChange: { focused in
                                        if !focused { commitSubnote() }
                                    },
                                    onDismiss: { commitSubnote() }
                                )
                                .frame(height: subnoteEditorHeight)
                                if newSubnoteText.isEmpty {
                                    Text("Add subnote…")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundColor(.secondary.opacity(0.28))
                                        .allowsHitTesting(false)
                                        .padding(.top, 1)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(squishColor.opacity(0.38), lineWidth: 1)
                                    )
                            )
                            .padding(.top, 10)
                            .onChange(of: newSubnoteText) { _, value in
                                subnoteAutoSaveTask?.cancel()
                                subnoteAutoSaveTask = Task {
                                    try? await Task.sleep(nanoseconds: 700_000_000)
                                    guard !Task.isCancelled else { return }
                                    await MainActor.run {
                                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmed.isEmpty {
                                            viewModel.autoSaveSubnoteDraft(parentId: note.id, text: trimmed)
                                        }
                                    }
                                }
                            }
                        }

                        Spacer().frame(height: 64)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                }
            }

            // Subnote button
            Button {
                withAnimation(JottMotion.content) { showingSubnoteInput = true }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle").font(.system(size: 12, weight: .semibold))
                    Text("New Subnote").font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(squishColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(squishColor.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(squishColor.opacity(0.22), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
            .opacity(showingSubnoteInput ? 0 : 1)
            .animation(JottMotion.micro, value: showingSubnoteInput)
        }
        .frame(minHeight: isFullScreen ? 0 : 480)
        .background(isDarkMode
            ? Color(red: 0.082, green: 0.082, blue: 0.090)
            : Color(red: 0.984, green: 0.984, blue: 0.990))
        .matchedGeometryEffect(
            id: "library-grid-card-\(note.id.uuidString)",
            in: animationNamespace,
            properties: .frame,
            anchor: .topLeading
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ds.hairlineMid, lineWidth: 1)
        )
        .onChange(of: note.id) { _, _ in
            subnoteAutoSaveTask?.cancel()
            newSubnoteText = ""
            subnoteEditorHeight = SubnoteTextEditor.minHeight
            showingSubnoteInput = false
        }
    }
}

// MARK: - DeleteConfirmOverlay

private struct DeleteConfirmOverlay: View {
    let count: Int
    let isPermanent: Bool
    let isDark: Bool
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var deleteHovered = false
    @State private var cancelHovered = false

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.30)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            // Card
            VStack(spacing: 0) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.red.opacity(0.78))
                }
                .padding(.bottom, 14)

                Text(isPermanent
                    ? "Delete forever?"
                    : "Delete \(count) \(count == 1 ? "note" : "notes")?"
                )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.92) : .black.opacity(0.86))
                    .padding(.bottom, 6)

                Text(isPermanent
                    ? "This can't be undone."
                    : "Moved notes stay in Recently Deleted until you delete them forever."
                )
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 22)

                HStack(spacing: 10) {
                    // Cancel
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(isDark ? .white.opacity(0.72) : .black.opacity(0.64))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isDark ? Color.white.opacity(cancelHovered ? 0.09 : 0.06)
                                                 : Color.black.opacity(cancelHovered ? 0.07 : 0.05))
                            )
                    }
                    .buttonStyle(SquishButtonStyle())
                    .onHover { cancelHovered = $0 }

                    // Delete
                    Button(action: onDelete) {
                        Text(isPermanent ? "Delete Forever" : "Delete")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.red.opacity(deleteHovered ? 0.82 : 0.68))
                            )
                    }
                    .buttonStyle(SquishButtonStyle())
                    .onHover { deleteHovered = $0 }
                }
            }
            .padding(24)
            .frame(width: 290)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isDark ? Color(red: 0.13, green: 0.13, blue: 0.145) : Color.white)
                    .shadow(color: .black.opacity(isDark ? 0.55 : 0.18), radius: 40, x: 0, y: 16)
            )
        }
    }
}

// MARK: - SquishButtonStyle

private struct SquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.91 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

// MARK: - Folder Icon View

private struct FolderIconView: View {
    let color: Color
    var size: CGFloat = 80

    var body: some View {
        Image(systemName: "folder.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: size, height: size * 0.84)
            .shadow(color: color.opacity(0.25), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Folder Card

private struct FolderCard: View {
    let folder: NoteFolder
    let noteCount: Int
    let isDark: Bool

    @State private var hovered = false

    private var ds: JottDS { JottDS(isDark: isDark) }

    // Creamy pastel tint derived from the folder color
    var body: some View {
        HStack(spacing: 12) {
            FolderIconView(color: folder.displayColor, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ds.ink)
                    .lineLimit(1)

                Text("\(noteCount) note\(noteCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(ds.inkFaint)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovered
                    ? folder.displayColor.opacity(isDark ? 0.12 : 0.09)
                    : (isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ds.hairline, lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { hovered = h } }
    }
}

// MARK: - Rename Folder Sheet

private struct RenameFolderSheet: View {
    @Binding var folderName: String
    let isDark: Bool
    let onRename: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var nameFieldFocused: Bool
    private var ds: JottDS { JottDS(isDark: isDark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Rename Folder")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ds.ink)

            TextField("Folder name", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFieldFocused)
                .onSubmit { commitIfValid() }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
                Button("Rename") { commitIfValid() }
                    .keyboardShortcut(.return)
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 280)
        .background(ds.canvas)
        .colorScheme(isDark ? .dark : .light)
        .onAppear { nameFieldFocused = true }
    }

    private func commitIfValid() {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onRename(trimmed)
    }
}

private struct MinimalFoldCorner: View {
    let isDarkMode: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 18))
                path.addLine(to: CGPoint(x: 18, y: 18))
                path.addLine(to: CGPoint(x: 18, y: 0))
            }
            .stroke(Color.jottBorder.opacity(isDarkMode ? 0.46 : 0.40), lineWidth: 1)
        }
        .frame(width: 18, height: 18)
    }
}

enum TimelineItem: Identifiable {
    case note(Note)
    case reminder(Reminder)

    var id: String {
        switch self {
        case .note(let note): return note.id.uuidString
        case .reminder(let reminder): return reminder.id.uuidString
        }
    }

    var date: Date {
        switch self {
        case .note(let note): return note.modifiedAt
        case .reminder(let reminder): return reminder.dueDate
        }
    }
}

struct TimelineItemView: View {
    let item: TimelineItem
    @ObservedObject var viewModel: OverlayViewModel
    let isSelected: Bool
    let onSelect: (NSEvent.ModifierFlags) -> Void
    @State private var hovered = false

    private var isDarkMode: Bool {
        viewModel.isDarkMode
    }

    var body: some View {
        let ds = JottDS(isDark: isDarkMode)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Date column — 82px mono
                VStack(alignment: .leading, spacing: 2) {
                    switch item {
                    case .note(let note):
                        Text(monoDate(note.modifiedAt))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(ds.inkFaint)
                            .tracking(0.3)
                        if note.isPinned {
                            Text("PINNED")
                                .font(.system(size: 8.5, design: .monospaced).weight(.medium))
                                .foregroundColor(ds.accent.opacity(0.45))
                                .tracking(0.5)
                        }
                    case .reminder(let reminder):
                        Text(monoDate(reminder.dueDate))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(ds.inkFaint)
                            .tracking(0.3)
                    }
                }
                .frame(width: 82, alignment: .leading)

                // Title + preview
                VStack(alignment: .leading, spacing: 2) {
                    switch item {
                    case .note(let note):
                        Text(noteTitle(for: note))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(ds.ink)
                            .lineLimit(1)
                        if let preview = notePreview(for: note) {
                            Text(preview)
                                .font(.system(size: 12))
                                .foregroundColor(ds.inkMute)
                                .lineLimit(1)
                        }
                    case .reminder(let reminder):
                        Text(reminder.text)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(ds.ink)
                            .lineLimit(1)
                        Text(formatTime(reminder.dueDate))
                            .font(.system(size: 12))
                            .foregroundColor(ds.inkFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Subnote badge
                if case .note(let note) = item {
                    let subCount = NoteStore.shared.subnoteCount(of: note.id)
                    if subCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 8, weight: .medium))
                            Text("\(subCount)")
                                .font(.system(size: 10.5, design: .monospaced))
                        }
                        .foregroundColor(ds.inkFaint)
                        .frame(width: 44, alignment: .trailing)
                    } else {
                        Spacer().frame(width: 44)
                    }
                }

                // Relative time
                Group {
                    switch item {
                    case .note(let note):
                        Text(relativeTime(note.modifiedAt))
                    case .reminder(let reminder):
                        Text(relativeTime(reminder.dueDate))
                    }
                }
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(ds.inkFaintest)
                .tracking(0.3)
                .frame(width: 54, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? ds.surfaceAlt : (hovered ? ds.surfaceAlt.opacity(0.7) : Color.clear))
            .overlay(alignment: .bottomTrailing) {
                if case .note(let note) = item,
                   let fid = note.folderId,
                   let folder = NoteStore.shared.folders.first(where: { $0.id == fid }) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                            .foregroundColor(folder.displayColor.opacity(0.70))
                        Text(folder.name)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(ds.inkFaintest.opacity(0.60))
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 6)
                }
            }
            // Hairline divider
            Rectangle()
                .fill(ds.hairline)
                .frame(height: 1)
                .padding(.horizontal, 12)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if case .note(let note) = item {
                Button {
                    if let url = NoteStore.shared.exportNoteAsMarkdown(note) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Export as Markdown", systemImage: "square.and.arrow.up")
                }
                Button("Delete", role: .destructive) {
                    withAnimation(JottMotion.content) { viewModel.deleteNote(note.id) }
                }
            }
        }
        .onTapGesture {
            onSelect(NSApp.currentEvent?.modifierFlags ?? [])
        }
        .onHover { hovering in
            withAnimation(JottMotion.micro) { hovered = hovering }
        }
        .animation(JottMotion.micro, value: hovered)
    }

    private func monoDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return f.string(from: date).uppercased()
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func noteTitle(for note: Note) -> String {
        note.blocks.lazy.compactMap(displayLine(for:)).first ?? "Untitled"
    }

    private func notePreview(for note: Note) -> String? {
        let lines = note.blocks.compactMap(displayLine(for:))
        guard lines.count > 1 else { return nil }
        return lines[1]
    }

    private func displayLine(for block: Block) -> String? {
        switch block.type {
        case .paragraph, .heading, .bulletItem, .numberedItem, .taskItem, .quote:
            let value = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        case .table:
            let columns = max(block.tableHeaders.count, block.tableRows.first?.count ?? 0)
            guard columns > 0 else { return "Table" }
            return "Table · \(columns) column\(columns == 1 ? "" : "s")"
        case .image:
            return block.imageAlt.isEmpty ? nil : block.imageAlt
        default:
            return nil
        }
    }
}

// MARK: - Search Results View

private struct SearchResultsView: View {
    let results: [SearchResult]
    let query: String
    let isDark: Bool
    let selectedNote: Note?
    var matchedFolders: [NoteFolder] = []
    let onSelect: (Note) -> Void
    var onSelectFolder: ((UUID) -> Void)? = nil

    private var ds: JottDS { JottDS(isDark: isDark) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Folder matches
                if !matchedFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FOLDERS")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(ds.inkFaintest)
                            .tracking(0.8)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(matchedFolders) { folder in
                                    Button {
                                        onSelectFolder?(folder.id)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(folder.displayColor)
                                            Text(folder.name)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(ds.ink)
                                            let count = NoteStore.shared.notes(inFolder: folder.id).count
                                            if count > 0 {
                                                Text("\(count)")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(ds.inkFaintest)
                                            }
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(ds.inkFaintest)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(folder.displayColor.opacity(isDark ? 0.10 : 0.07))
                                        .clipShape(Capsule(style: .continuous))
                                        .overlay(Capsule(style: .continuous)
                                            .strokeBorder(folder.displayColor.opacity(0.25), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 16)

                    if !results.isEmpty {
                        Divider().opacity(isDark ? 0.10 : 0.08).padding(.bottom, 12)

                        Text("NOTES")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(ds.inkFaintest)
                            .tracking(0.8)
                            .padding(.bottom, 8)
                    }
                }

                if results.isEmpty && matchedFolders.isEmpty {
                    SearchResultsEmptyState(
                        title: "No results",
                        query: query
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(results) { result in
                            SearchResultRow(
                                result: result,
                                query: query,
                                isDark: isDark,
                                isSelected: {
                                    switch result {
                                    case .rootNote(let n, _): return selectedNote?.id == n.id
                                    case .subnote(_, let p, _): return selectedNote?.id == p.id
                                    }
                                }(),
                                onSelect: {
                                    switch result {
                                    case .rootNote(let n, _): onSelect(n)
                                    case .subnote(_, let p, _): onSelect(p)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    var query: String = ""
    let isDark: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var hovered = false

    private var accentColor: Color {
        isDark
            ? Color(red: 0.58, green: 0.50, blue: 0.92)
            : Color(red: 0.62, green: 0.52, blue: 0.96)
    }

    private var note: Note { result.note }
    private var isSubnote: Bool { result.isSubnote }

    private var title: String {
        cleanedNoteLines
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? "Untitled"
    }

    private var bodyPreview: String? {
        let lines = cleanedNoteLines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return nil }
        return lines.dropFirst().prefix(2).joined(separator: "  ·  ")
    }

    private var cleanedNoteLines: [String] {
        note.blocks.compactMap(displayLine(for:))
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: note.modifiedAt)
    }

    private var rowFill: Color {
        if isSelected { return isDark ? Color.white.opacity(0.072) : Color.black.opacity(0.055) }
        if hovered    { return isDark ? Color.white.opacity(0.04)  : Color.black.opacity(0.03) }
        return Color.clear
    }

    private var rowBorder: Color {
        if isSelected {
            return isSubnote
                ? accentColor.opacity(0.38)
                : Color.jottOverlayCoralAccent.opacity(isDark ? 0.40 : 0.30)
        }
        return Color.jottBorder.opacity(hovered ? 0.42 : 0.0)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                rowIcon
                rowContent
                Spacer()
                Text(dateLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, isSubnote ? 7 : 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(rowFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(rowBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { hovered = hovering }
        }
    }

    @ViewBuilder
    private var rowIcon: some View {
        if isSubnote {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(accentColor.opacity(0.75))
                .frame(width: 18)
        } else {
            Image(systemName: "note.text")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.45))
                .frame(width: 18)
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        let highlightColor = isDark
            ? Color(red: 0.58, green: 0.50, blue: 0.92)
            : Color(red: 0.50, green: 0.40, blue: 0.88)

        VStack(alignment: .leading, spacing: 2) {
            if isSubnote, let parent = result.parentNote {
                Text(parentTitle(parent))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.40))
                    .lineLimit(1)
            }
            HighlightedText(
                text: title,
                query: query,
                font: .system(size: 13, weight: isSubnote ? .regular : .medium),
                baseColor: isDark ? .white.opacity(0.88) : .black.opacity(0.84),
                highlightColor: highlightColor
            )
            .lineLimit(1)
            if !isSubnote, let preview = bodyPreview {
                HighlightedText(
                    text: preview,
                    query: query,
                    font: .system(size: 11.5),
                    baseColor: .secondary.opacity(0.50),
                    highlightColor: highlightColor.opacity(0.80)
                )
                .lineLimit(1)
            }
        }
    }

    private func parentTitle(_ parent: Note) -> String {
        parent.blocks.compactMap(displayLine(for:)).first ?? "Untitled"
    }

    private func displayLine(for block: Block) -> String? {
        switch block.type {
        case .paragraph, .heading, .bulletItem, .numberedItem, .taskItem, .quote:
            let value = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        case .table:
            let columns = max(block.tableHeaders.count, block.tableRows.first?.count ?? 0)
            guard columns > 0 else { return "Table" }
            return "Table · \(columns) column\(columns == 1 ? "" : "s")"
        case .image:
            return block.imageAlt.isEmpty ? nil : block.imageAlt
        default:
            return nil
        }
    }
}

// MARK: - Folder Strip

private struct FolderStrip: View {
    @ObservedObject var noteStore: NoteStore
    let folderStack: [UUID]
    let isDark: Bool
    let onPop: () -> Void
    let onPush: (UUID) -> Void
    var onAddFolder: (() -> Void)? = nil
    var onRenameFolder: ((NoteFolder) -> Void)? = nil

    @State private var isCreating = false
    @State private var newName = ""
    @State private var newColor: FolderColorTag = .lavender
    @State private var showColorPicker = false
    @FocusState private var fieldFocused: Bool

    private var ds: JottDS { JottDS(isDark: isDark) }

    private var visibleFolders: [NoteFolder] {
        if let current = folderStack.last {
            return noteStore.subfolders(of: current)
        }
        return noteStore.folders.filter { $0.parentId == nil }
    }

    private var breadcrumb: [NoteFolder] {
        folderStack.compactMap { id in noteStore.folders.first(where: { $0.id == id }) }
    }

    private func commitNew() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { cancelNew(); return }
        _ = NoteStore.shared.createFolder(name: trimmed, colorTag: newColor, parentId: folderStack.last)
        cancelNew()
    }

    private func cancelNew() {
        showColorPicker = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            isCreating = false
            newName = ""
            newColor = .lavender
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Back + path when inside a folder
                if !folderStack.isEmpty {
                    Button(action: onPop) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                            if let folder = breadcrumb.last {
                                Text(folder.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                        }
                        .foregroundColor(ds.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ds.accentSoft)
                        .clipShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if breadcrumb.count > 1 {
                        ForEach(Array(breadcrumb.dropLast().enumerated()), id: \.element.id) { i, f in
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(ds.inkFaintest)
                            Button {
                                onPop()
                            } label: {
                                Text(f.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(ds.inkFaint)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !visibleFolders.isEmpty {
                        Rectangle()
                            .fill(ds.hairlineMid)
                            .frame(width: 1, height: 16)
                    }
                }

                // Folder chips
                ForEach(visibleFolders) { folder in
                    FolderChip(folder: folder, isDark: isDark) {
                        onPush(folder.id)
                    }
                    .contextMenu {
                        Button("Rename") { onRenameFolder?(folder) }
                        Divider()
                        Button(role: .destructive) {
                            NoteStore.shared.deleteFolder(folder.id)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }

                // Inline creation field (replaces + button while active)
                if isCreating {
                    HStack(spacing: 8) {
                        // Folder icon — tap opens color popover
                        Button {
                            showColorPicker.toggle()
                        } label: {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(newColor.color)
                                .animation(.easeInOut(duration: 0.15), value: newColor)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                            HStack(spacing: 6) {
                                ForEach(FolderColorTag.allCases, id: \.self) { tag in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.12)) { newColor = tag }
                                        showColorPicker = false
                                    } label: {
                                        ZStack {
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(tag.color)
                                            if newColor == tag {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 7, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .frame(width: 32, height: 32)
                                        .background(newColor == tag ? tag.color.opacity(0.15) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(10)
                        }

                        TextField("Folder name", text: $newName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ds.ink)
                            .focused($fieldFocused)
                            .frame(minWidth: 90, maxWidth: 150)
                            .onSubmit { commitNew() }

                        // Confirm
                        Button(action: commitNew) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(newName.trimmingCharacters(in: .whitespaces).isEmpty ? ds.inkFaintest : ds.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)

                        // Cancel
                        Button(action: cancelNew) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(ds.inkFaint)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(ds.surfaceAlt)
                    .clipShape(Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).strokeBorder(ds.accentRing, lineWidth: 1))
                    .transition(.scale(scale: 0.88, anchor: .leading).combined(with: .opacity))
                } else {
                    // + button
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            isCreating = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fieldFocused = true }
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ds.accent)
                            .frame(width: 28, height: 28)
                            .background(ds.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("New folder")
                    .transition(.scale(scale: 0.88, anchor: .leading).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isCreating)
        .animation(JottMotion.content, value: folderStack.map(\.uuidString).joined())
    }
}

private struct FolderChip: View {
    let folder: NoteFolder
    let isDark: Bool
    let onTap: () -> Void

    @State private var hovered = false
    private var ds: JottDS { JottDS(isDark: isDark) }
    private var noteCount: Int { NoteStore.shared.notes(inFolder: folder.id).count }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(folder.displayColor)
                Text(folder.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(hovered ? ds.ink : ds.inkMute)
                    .lineLimit(1)
                if noteCount > 0 {
                    Text("\(noteCount)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(ds.inkFaintest)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                hovered
                    ? folder.displayColor.opacity(isDark ? 0.12 : 0.07)
                    : (isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(hovered ? folder.displayColor.opacity(0.35) : ds.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { hovered = h } }
    }
}

// MARK: - Top Bar

private struct LibraryTopBar: View {
    @Binding var searchText: String
    @Binding var activeFilter: LibraryFilter
    let visibleCount: Int
    var selectedCount: Int = 0
    let isDarkMode: Bool
    let selectedNote: Note?
    var availableTags: [String] = []
    var destructiveActionLabel: String = "Delete"
    var onDismissDetail: (() -> Void)? = nil
    var onDeleteSelected: (() -> Void)? = nil
    var onNewNote: (() -> Void)? = nil

    @State private var showFilterPopover = false
    private var isSearching: Bool { !searchText.isEmpty }
    private var hasSelection: Bool { selectedCount > 1 }

    var body: some View {
        let ds = JottDS(isDark: isDarkMode)

        HStack(spacing: 12) {
            // Title + inline mono count
            HStack(spacing: 7) {
                Text("Notes")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(ds.ink)
                Text("\(visibleCount)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(ds.inkFaintest)
                    .tracking(0.3)
            }

            // Multi-select action bar
            if hasSelection {
                HStack(spacing: 8) {
                    Text("\(selectedCount) selected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ds.inkMute)

                    Button {
                        onDeleteSelected?()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                                .font(.system(size: 10.5, weight: .medium))
                            Text(destructiveActionLabel)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(red: 0.90, green: 0.28, blue: 0.28))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
            }

            Spacer(minLength: 0)

            if !isSearching {
                Button {
                    activeFilter = activeFilter == .recentlyDeleted ? .none : .recentlyDeleted
                } label: {
                    Text("Recently Deleted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(activeFilter == .recentlyDeleted ? ds.accent : ds.inkFaint)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(activeFilter == .recentlyDeleted ? ds.accentSoft : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help("Recently Deleted")

                Button {
                    if let zipURL = NoteStore.shared.exportAllNotesAsZip() {
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "jott-export.zip"
                        panel.begin { result in
                            if result == .OK, let dest = panel.url {
                                try? FileManager.default.copyItem(at: zipURL, to: dest)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ds.inkFaint)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Export All Notes")
            }

            // Filter button
            if !isSearching {
                Button {
                    showFilterPopover.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(activeFilter.isActive ? ds.accent : ds.inkFaint)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(activeFilter.isActive ? ds.accentSoft : Color.clear)
                            )
                        if activeFilter.isActive {
                            Circle()
                                .fill(ds.accent)
                                .frame(width: 6, height: 6)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
                    LibraryFilterPopover(
                        activeFilter: $activeFilter,
                        availableTags: availableTags,
                        isDark: isDarkMode
                    )
                }
            }

            // Search field
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSearching ? ds.accent : ds.inkFaint)
                    .animation(.easeInOut(duration: 0.15), value: isSearching)

                TextField("Search…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundColor(ds.ink)
                    .frame(width: 160)

                if isSearching {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(ds.inkFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSearching ? ds.accentRing : ds.hairlineMid,
                        lineWidth: 1
                    )
                    .animation(.easeInOut(duration: 0.18), value: isSearching)
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(height: 68)
        .background(isDarkMode ? Color.white.opacity(0.006) : Color.white.opacity(0.80))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSearching)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: hasSelection)
    }

}

// MARK: - Filter Popover

private struct LibraryFilterPopover: View {
    @Binding var activeFilter: LibraryFilter
    let availableTags: [String]
    let isDark: Bool

    private var ds: JottDS { JottDS(isDark: isDark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FILTER")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(ds.inkFaintest)
                .tracking(0.8)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            filterRow(.none,      icon: "tray.full",       label: "All notes")
            filterRow(.pinned,    icon: "pin.fill",        label: "Pinned")
            filterRow(.today,     icon: "sun.max",         label: "Today")
            filterRow(.thisWeek,  icon: "calendar.badge.clock", label: "This week")
            filterRow(.thisMonth, icon: "calendar",        label: "This month")

            Divider().opacity(0.12).padding(.vertical, 6)
            filterRow(.recentlyDeleted, icon: "trash", label: "Recently Deleted")

            if !availableTags.isEmpty {
                Divider().opacity(0.12).padding(.vertical, 6)
                Text("TAGS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(ds.inkFaintest)
                    .tracking(0.8)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)

                ForEach(availableTags, id: \.self) { tag in
                    filterRow(.tagged(tag), icon: "number", label: tag)
                }
            }

            Spacer().frame(height: 8)
        }
        .frame(width: 200)
        .background(ds.surface)
        .colorScheme(isDark ? .dark : .light)
    }

    private func filterRow(_ filter: LibraryFilter, icon: String, label: String) -> some View {
        let isActive = activeFilter == filter
        return Button {
            activeFilter = filter
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isActive ? ds.accent : ds.inkFaint)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(isActive ? ds.ink : ds.inkMute)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ds.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isActive ? ds.accentSoft : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryStatChip: View {
    let label: String
    let value: Int
    let isDarkMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            Text("\(value)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(0.82))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.jottOverlaySurface.opacity(isDarkMode ? 0.84 : 0.74))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.jottBorder.opacity(0.88), lineWidth: 1)
        )
    }
}

private struct FolderEmptyState: View {
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .center) {
            // "Empty." dead center
            Text("Empty.")
                .font(.system(size: 72, weight: .bold, design: .default))
                .foregroundColor(.primary.opacity(0.07))
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

            // Subtitle pinned to bottom-right
            VStack(alignment: .trailing, spacing: 6) {
                Spacer()
                Text("Nothing in this folder yet.")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundColor(.primary.opacity(0.32))
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
                Text("Right-click any note and choose Move to Folder.")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundColor(.secondary.opacity(0.35))
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.04)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }
}

private struct LibraryEmptyState: View {
    let title: String
    let message: String
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            VStack(alignment: .trailing, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.22))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.18))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.bottom, 24)
            .padding(.trailing, 2)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(0.08)) { appeared = true }
        }
        .onDisappear { appeared = false }
    }
}

private struct SearchResultsEmptyState: View {
    let title: String
    let query: String

    var body: some View {
        VStack(spacing: 18) {
            Text(title)
                .font(JottTypography.title(40, weight: .semibold))
                .foregroundColor(.primary.opacity(0.92))

            Text("Nothing matched \"\(query)\"")
                .font(JottTypography.noteBody(20, weight: .medium))
                .foregroundColor(.secondary.opacity(0.72))
                .multilineTextAlignment(.center)

            Text("Try a broader term or a more exact phrase.")
                .font(JottTypography.ui(16, weight: .medium))
                .foregroundColor(.secondary.opacity(0.56))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 520, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 32)
    }
}

private struct LibrarySelectionEmptyState: View {
    let isDarkMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(JottTypography.title(15, weight: .semibold))
                .foregroundColor(.primary)
            Text("Select a note or reminder to inspect it here.")
                .font(JottTypography.noteBody(13))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(2)
    }
}

struct LibraryNoteInspector: View {
    let note: Note
    @ObservedObject var viewModel: OverlayViewModel
    let editRequestToken: UUID
    let onSelectNote: (Note) -> Void
    @State private var isEditing = false
    @State private var editingBlocks: [Block] = []
    @FocusState private var isEditorFocused: Bool

    private var isDarkMode: Bool {
        viewModel.isDarkMode
    }

    private var displayBlocks: [Block] {
        jottDisplayBlocks(from: note.blocks)
    }

    private var title: String {
        if let textTitle = displayBlocks.lazy.compactMap(textTitle(for:)).first {
            return textTitle
        }
        if let table = displayBlocks.first(where: { $0.type == .table }) {
            let columns = max(table.tableHeaders.count, table.tableRows.first?.count ?? 0)
            return columns > 0 ? "Table · \(columns) column\(columns == 1 ? "" : "s")" : "Table"
        }
        return "Untitled"
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: note.modifiedAt, relativeTo: Date())
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                tagsSection
                contentSection
            }
        }
        .onAppear {
            resetEditingState()
            isEditing = true
            DispatchQueue.main.async { isEditorFocused = true }
        }
        .onChange(of: note.id) { _, _ in
            resetEditingState()
            isEditing = true
            DispatchQueue.main.async { isEditorFocused = true }
        }
        .onChange(of: editRequestToken) { _, _ in
            resetEditingState()
            isEditing = true
            DispatchQueue.main.async { isEditorFocused = true }
        }
        .onChange(of: note.modifiedAt) { _, _ in
            if !isEditing {
                editingBlocks = note.blocks
            }
        }
    }

    private func resetEditingState() {
        let blocks = jottDisplayBlocks(from: note.blocks)
        editingBlocks = blocks.isEmpty ? [Block(type: .paragraph, spans: [TextSpan("")])] : blocks
    }

    private func textTitle(for block: Block) -> String? {
        switch block.type {
        case .paragraph, .heading, .bulletItem, .numberedItem, .taskItem, .quote:
            let value = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !(value.hasPrefix("|") && value.hasSuffix("|")) else { return nil }
            return value.isEmpty ? nil : value
        default:
            return nil
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(title)
                    .font(JottTypography.title(21, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                actionButtons
            }
            Text("Updated \(relativeDate)")
                .font(JottTypography.ui(11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.jottOverlayPeachAccent.opacity(0.86))
                    .padding(8)
                    .background(Color.jottOverlayWarmAccent.opacity(isDarkMode ? 0.16 : 0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Button(isEditing ? "Save" : "Edit") {
                if isEditing {
                    if let updated = viewModel.updateNote(note, blocks: editingBlocks) {
                        editingBlocks = updated.blocks
                        isEditing = false
                    }
                } else {
                    resetEditingState()
                    isEditing = true
                }
            }
            .buttonStyle(.plain)
            .font(JottTypography.ui(11, weight: .semibold))
            .foregroundColor(.primary.opacity(0.78))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isDarkMode ? Color.white.opacity(0.025) : Color.black.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.jottBorder.opacity(0.56), lineWidth: 1))

            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("com.casualhermit.jott.openNoteInCanvas"),
                    object: note.id
                )
            } label: {
                inspectorIconButton(systemName: "point.3.connected.trianglepath.dotted")
            }
            .buttonStyle(.plain)

            Button { viewModel.openNoteInEditor(note) } label: {
                inspectorIconButton(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.plain)
        }
    }

    private func inspectorIconButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.78))
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isDarkMode ? Color.white.opacity(0.025) : Color.black.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.jottBorder.opacity(0.56), lineWidth: 1))
    }

    @ViewBuilder
    private var tagsSection: some View {
        if !note.tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(note.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(JottTypography.ui(11, weight: .semibold))
                        .foregroundColor(Color.tagColor(for: tag))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.tagColor(for: tag).opacity(isDarkMode ? 0.18 : 0.14)))
                }
            }
        }
    }

    private var contentSection: some View {
        Group {
            if isEditing {
                LibraryBlockEditor(blocks: $editingBlocks, isDarkMode: isDarkMode)
            } else {
                NoteBlockRichContentView(
                    blocks: displayBlocks,
                    isDarkMode: isDarkMode,
                    onTap: {
                        resetEditingState()
                        isEditing = true
                        isEditorFocused = true
                    }
                )
            }
        }
        .padding(14)
        .background(isDarkMode ? Color.white.opacity(0.018) : Color.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.jottBorder.opacity(0.60), lineWidth: 1))
    }
}

struct LibraryBlockEditor: View {
    @Binding var blocks: [Block]
    let isDarkMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryNoteTextEditor(blocks: textBlocksBinding, isDark: isDarkMode)
                .frame(minHeight: 180)
            ForEach(imageIndices, id: \.self) { i in
                if let path = blocks[i].imageURL, !path.isEmpty {
                    AttachmentImageView(path: path, alt: blocks[i].imageAlt)
                        .padding(.top, 8)
                }
            }
            ForEach(tableIndices, id: \.self) { i in
                LibraryStoredTableEditor(block: $blocks[i])
                    .padding(.top, 8)
            }
        }
    }

    private var imageIndices: [Int] {
        blocks.indices.filter { blocks[$0].type == .image }
    }

    private var tableIndices: [Int] {
        blocks.indices.filter { blocks[$0].type == .table }
    }

    private var textBlocksBinding: Binding<[Block]> {
        Binding(
            get: { blocks.filter { $0.type != .table && $0.type != .image } },
            set: { newText in
                var merged = newText
                merged.append(contentsOf: blocks.filter { $0.type == .table || $0.type == .image })
                blocks = merged
            }
        )
    }
}

private struct LibraryEditFormatBar: View {
    @Binding var blocks: [Block]

    var body: some View {
        HStack(spacing: 2) {
            button("B", command: .bold, bold: true)
            button("I", command: .italic, italic: true)
            button("U", command: .underline, underline: true)
            button("S", command: .strikethrough, strike: true)
            icon("highlighter", command: .highlight)
            sep
            icon("list.bullet", command: .bulletList)
            icon("list.number", command: .numberedList)
            icon("checklist", command: .taskList)
            icon("text.quote", command: .quote)
            sep
            icon("chevron.left.forwardslash.chevron.right", command: .inlineCode)
            icon("textformat.size", command: .heading)
            icon("link", command: .link)
            tableMenu
        }
    }

    private var sep: some View {
        Rectangle().fill(Color.secondary.opacity(0.18)).frame(width: 1, height: 13).padding(.horizontal, 3)
    }

    private var tableMenu: some View {
        Menu {
            Button("2 x 2") { insertTable(rows: 2, columns: 2) }
            Button("3 x 3") { insertTable(rows: 3, columns: 3) }
            Button("4 x 4") { insertTable(rows: 4, columns: 4) }
            Button("6 x 4") { insertTable(rows: 4, columns: 6) }
        } label: {
            Image(systemName: "tablecells")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func apply(_ command: JottTextFormatCommand) {
        if let tv = JottTextFormattingRegistry.activeTextView as? JottLibraryTextView, tv.window != nil {
            tv.window?.makeFirstResponder(tv)
            if tv.applyLibraryFormat(command) { return }
        }

        if blocks.isEmpty {
            blocks.append(Block(type: .paragraph, spans: [TextSpan("")]))
        }
        switch command {
        case .bulletList:
            blocks[0].type = .bulletItem
        case .numberedList:
            blocks[0].type = .numberedItem
        case .taskList:
            blocks[0].type = .taskItem
            blocks[0].checked = false
        case .quote:
            blocks[0].type = .quote
        case .heading:
            blocks[0].type = .heading
            blocks[0].level = 1
        default:
            break
        }
    }

    private func insertTable(rows: Int, columns: Int) {
        blocks.append(JottDraftTable(rows: rows, columns: columns).block)
    }

    private func button(_ label: String, command: JottTextFormatCommand, bold: Bool = false, italic: Bool = false, underline: Bool = false, strike: Bool = false) -> some View {
        Button { apply(command) } label: {
            Group {
                if bold { Text(label).bold() }
                else if italic { Text(label).italic() }
                else if underline { Text(label).underline() }
                else if strike { Text(label).strikethrough() }
                else { Text(label) }
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }

    private func icon(_ systemName: String, command: JottTextFormatCommand) -> some View {
        Button { apply(command) } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
}

struct LibraryStoredTableEditor: View {
    @Binding var block: Block
    @FocusState private var focusedCell: String?

    private var headers: [String] {
        block.tableHeaders.isEmpty ? ["Column 1", "Column 2"] : block.tableHeaders
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    tableGrid

                    tableButton(systemName: "plus", width: 24, action: addColumn)
                        .help("Add column")
                        .padding(.top, 6)
                }

                tableButton(systemName: "plus", width: CGFloat(headers.count) * 112, action: addRow)
                    .help("Add row")
            }
        }
    }

    private var tableGrid: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(headers.indices, id: \.self) { column in
                    cell(
                        text: Binding(
                            get: { header(column) },
                            set: { setHeader($0, column: column) }
                        ),
                        id: "h-\(column)",
                        isHeader: true
                    )
                }
            }

            ForEach(block.tableRows.indices, id: \.self) { row in
                GridRow {
                    ForEach(headers.indices, id: \.self) { column in
                        cell(
                            text: Binding(
                                get: { value(row: row, column: column) },
                                set: { setValue($0, row: row, column: column) }
                            ),
                            id: "\(row)-\(column)",
                            isHeader: false
                        )
                    }
                }
            }
        }
        .background(Color.secondary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.jottBorder.opacity(0.7), lineWidth: 1))
    }

    private func tableButton(systemName: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.70))
                .frame(width: width, height: 24)
                .background(Color.jottOverlaySurface.opacity(0.94), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.jottBorder.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func cell(text: Binding<String>, id: String, isHeader: Bool) -> some View {
        TextField("", text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: isHeader ? .semibold : .regular))
            .foregroundColor(.primary.opacity(isHeader ? 0.90 : 0.82))
            .focused($focusedCell, equals: id)
            .padding(.horizontal, 10)
            .frame(minWidth: 112, minHeight: 34, alignment: .leading)
            .background(isHeader ? Color.secondary.opacity(0.09) : Color.secondary.opacity(0.035))
            .overlay(Rectangle()
                .stroke(Color.jottBorder.opacity(focusedCell == id ? 0.95 : 0.55),
                        lineWidth: focusedCell == id ? 1.1 : 0.55))
    }

    private func header(_ column: Int) -> String {
        ensureTableShape()
        return block.tableHeaders.indices.contains(column) ? block.tableHeaders[column] : ""
    }

    private func setHeader(_ value: String, column: Int) {
        ensureTableShape()
        while block.tableHeaders.count <= column {
            block.tableHeaders.append("Column \(block.tableHeaders.count + 1)")
        }
        block.tableHeaders[column] = value
    }

    private func value(row: Int, column: Int) -> String {
        ensureTableShape()
        guard block.tableRows.indices.contains(row), block.tableRows[row].indices.contains(column) else { return "" }
        return block.tableRows[row][column]
    }

    private func setValue(_ value: String, row: Int, column: Int) {
        ensureTableShape()
        guard block.tableRows.indices.contains(row) else { return }
        while block.tableRows[row].count <= column {
            block.tableRows[row].append("")
        }
        block.tableRows[row][column] = value
    }

    private func addRow() {
        ensureTableShape()
        block.tableRows.append(Array(repeating: "", count: block.tableHeaders.count))
    }

    private func addColumn() {
        ensureTableShape()
        block.tableHeaders.append("Column \(block.tableHeaders.count + 1)")
        for row in block.tableRows.indices {
            block.tableRows[row].append("")
        }
    }

    private func ensureTableShape() {
        if block.tableHeaders.isEmpty {
            block.tableHeaders = ["Column 1", "Column 2"]
        }
        if block.tableRows.isEmpty {
            block.tableRows = [Array(repeating: "", count: block.tableHeaders.count)]
        }
        for row in block.tableRows.indices where block.tableRows[row].count < block.tableHeaders.count {
            block.tableRows[row] += Array(repeating: "", count: block.tableHeaders.count - block.tableRows[row].count)
        }
    }
}

private final class JottLibraryTextView: NSTextView {
    var libraryFormatHandler: ((JottTextFormatCommand) -> Bool)?
    var onEscape: (() -> Void)? = nil
    var onCmdReturn: (() -> Void)? = nil
    var onCommandShiftF: (() -> Void)? = nil
    var onCommandShiftM: (() -> Void)? = nil
    var onCommandShiftK: (() -> Void)? = nil
    var onCommandShiftX: (() -> Void)? = nil
    var onBackspaceOnEmpty: (() -> Void)? = nil
    var onUndo: (() -> Void)? = nil
    
    var lastKnownSelectedRange = NSRange(location: 0, length: 0)

    func applyLibraryFormat(_ command: JottTextFormatCommand) -> Bool {
        libraryFormatHandler?(command) ?? false
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            JottTextFormattingRegistry.activeTextView = self
            JottTextFormattingRegistry.libraryFormatHandler = { [weak self] cmd in
                self?.applyLibraryFormat(cmd) ?? false
            }
            let currentSelection = selectedRange()
            if currentSelection.location != 0 || lastKnownSelectedRange.location == 0 {
                lastKnownSelectedRange = currentSelection
            }
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        // Keep the editor registered while toolbar buttons take focus.
        // The formatting bar lives outside NSTextView, so clearing this here
        // makes list buttons fall back to mutating blocks[0] instead of the
        // line/selection the user was editing.
        lastKnownSelectedRange = selectedRange()
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = modifiers.contains(.command)
        let hasShift = modifiers.contains(.shift)
        
        if event.keyCode == 53 { // ESC
            if let onEscape = onEscape { onEscape(); return true }
            return super.performKeyEquivalent(with: event)
        }
        
        if event.keyCode == 36 && hasCommand { // Cmd+Return
            if let onCmdReturn = onCmdReturn { onCmdReturn(); return true }
        }
        
        if event.keyCode == 51 && !hasCommand && !hasShift && !modifiers.contains(.option) && !modifiers.contains(.control) && (string.isEmpty || string == "\n") { // Backspace
            if let onBackspaceOnEmpty = onBackspaceOnEmpty { onBackspaceOnEmpty(); return true }
        }



        // Tab auto-completes partial slash commands (e.g. /sea<Tab> → /search )
        if event.keyCode == 48,
           !hasCommand, !hasShift, !modifiers.contains(.option), !modifiers.contains(.control),
           string.hasPrefix("/") {
            let query = String(string.dropFirst()).lowercased()
            if let match = allCommandChips.first(where: {
                $0.label.lowercased().hasPrefix(query) ||
                String($0.shorthand.dropFirst()).hasPrefix(query) ||
                String($0.insert.dropFirst()).hasPrefix(query)
            }) {
                self.string = match.insert
                self.setSelectedRange(NSRange(location: match.insert.count, length: 0))
                return true
            }
        }

        if hasCommand && hasShift {
            switch event.charactersIgnoringModifiers {
            case "f", "F": onCommandShiftF?(); return true
            case "m", "M": onCommandShiftM?(); return true
            case "k", "K": onCommandShiftK?(); return true
            case "x", "X": onCommandShiftX?(); return true
            default: break
            }
        }
        
        guard hasCommand, !hasShift,
              !modifiers.contains(.option),
              !modifiers.contains(.control) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "b": _ = applyLibraryFormat(.bold); return true
        case "i": _ = applyLibraryFormat(.italic); return true
        case "u": _ = applyLibraryFormat(.underline); return true
        case "e": _ = applyLibraryFormat(.inlineCode); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

// MARK: - Block-aware NSTextView editor

private let kJBType    = NSAttributedString.Key("JottBlockType")
private let kJBLevel   = NSAttributedString.Key("JottBlockLevel")
private let kJBChecked = NSAttributedString.Key("JottBlockChecked")
private let kJBImageURL = NSAttributedString.Key("JottBlockImageURL")

struct LibraryNoteTextEditor: NSViewRepresentable {
    @Binding var blocks: [Block]
    let isDark: Bool
    
    var placeholder: String = ""
    var isFocused: Bool = false
    /// Override the NSTextView's textContainerInset (default is 4pt top/bottom as in Library)
    var textInset: NSSize = NSSize(width: 0, height: 4)
    /// Override lineFragmentPadding (default 2 as in Library)
    var lineFragmentPadding: CGFloat = 2
    var onEscape: (() -> Void)? = nil
    var onCmdReturn: (() -> Void)? = nil
    var onToggleFormatShortcut: (() -> Void)? = nil
    var onToggleVoiceShortcut: (() -> Void)? = nil
    var onClearTagFilterShortcut: (() -> Void)? = nil
    var onClearClipboardShortcut: (() -> Void)? = nil
    var onBackspaceOnEmpty: (() -> Void)? = nil
    var onUndo: (() -> Void)? = nil
    var onHeightChange: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller = false
        sv.drawsBackground = false
        sv.borderType = .noBorder

        let tv = JottLibraryTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.lineFragmentPadding = lineFragmentPadding
        tv.textContainerInset = textInset

        sv.documentView = tv
        context.coordinator.tv = tv
        let coordinator = context.coordinator
        tv.libraryFormatHandler = { [weak coordinator, weak tv] command in
            guard let coordinator, let tv else { return false }
            return coordinator.applyFormat(command, in: tv)
        }
        tv.onEscape = onEscape
        tv.onCmdReturn = onCmdReturn
        tv.onCommandShiftF = onToggleFormatShortcut
        tv.onCommandShiftM = onToggleVoiceShortcut
        tv.onCommandShiftK = onClearTagFilterShortcut
        tv.onCommandShiftX = onClearClipboardShortcut
        tv.onBackspaceOnEmpty = onBackspaceOnEmpty
        tv.onUndo = onUndo
        
        context.coordinator.load(blocks, into: tv)
        DispatchQueue.main.async {
            if self.isFocused { tv.window?.makeFirstResponder(tv) }
            context.coordinator.reportHeight(from: tv)
        }
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? JottLibraryTextView else { return }
        context.coordinator.parent = self
        
        tv.onEscape = onEscape
        tv.onCmdReturn = onCmdReturn
        tv.onCommandShiftF = onToggleFormatShortcut
        tv.onCommandShiftM = onToggleVoiceShortcut
        tv.onCommandShiftK = onClearTagFilterShortcut
        tv.onCommandShiftX = onClearClipboardShortcut
        tv.onBackspaceOnEmpty = onBackspaceOnEmpty
        tv.onUndo = onUndo
        
        if isFocused && tv.window?.firstResponder != tv {
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
        
        // Never reload storage while the coordinator is mid-edit (typing, Enter continuation, etc.)
        guard !context.coordinator.suppressSync else { return }
        
        let proposed = context.coordinator.displayString(for: blocks)
        let current = context.coordinator.withoutTrailingNewlines(tv.string)
        let comparableProposed = context.coordinator.withoutTrailingNewlines(proposed)
        if current != comparableProposed {
            context.coordinator.load(blocks, into: tv)
            DispatchQueue.main.async {
                context.coordinator.reportHeight(from: tv)
            }
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LibraryNoteTextEditor
        weak var tv: NSTextView?
        var suppressSync = false

        init(_ parent: LibraryNoteTextEditor) { self.parent = parent }

        func withoutTrailingNewlines(_ text: String) -> String {
            var result = text
            while result.hasSuffix("\n") {
                result.removeLast()
            }
            return result
        }
        
        func reportHeight(from tv: NSTextView) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            var h = lm.usedRect(for: tc).height
            if h < 10, let font = tv.font { h = font.ascender + abs(font.descender) }
            let finalHeight = ceil(h + tv.textContainerInset.height * 2)
            parent.onHeightChange?(finalHeight)
        }

        // MARK: Load blocks → attributed string

        func load(_ blocks: [Block], into tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let saved = tv.selectedRange()
            storage.beginEditing()
            storage.setAttributedString(makeAttributedString(blocks))
            storage.endEditing()
            tv.setSelectedRange(NSRange(location: min(saved.location, storage.length), length: 0))
            updateTypingAttrs(tv)
        }

        func makeAttributedString(_ blocks: [Block]) -> NSAttributedString {
            let out = NSMutableAttributedString()
            var nIdx = 1
            for (i, b) in blocks.enumerated() {
                if i > 0 { out.append(NSAttributedString(string: "\n", attributes: paraAttrs(parent.isDark))) }
                out.append(makeBlockAttrString(b, nIdx: nIdx, dark: parent.isDark))
                if b.type == .numberedItem { nIdx += 1 } else { nIdx = 1 }
            }
            return out
        }

        // Builds a fully-attributed NSAttributedString for one block, including per-span bold/italic/etc.
        private func makeBlockAttrString(_ b: Block, nIdx: Int, dark: Bool) -> NSAttributedString {
            switch b.type {
            case .divider:
                return NSAttributedString(string: "─────────────────────", attributes: dividerAttrs(dark: dark))
            case .image:
                let placeholder = b.imageAlt.isEmpty ? " " : b.imageAlt
                var attrs = paraAttrs(dark)
                if let url = b.imageURL { attrs[kJBImageURL] = url }
                attrs[kJBType] = BlockType.image.rawValue
                return NSAttributedString(string: placeholder, attributes: attrs)
            default: break
            }

            let blockAttrs: [NSAttributedString.Key: Any]
            let prefix: String
            switch b.type {
            case .bulletItem:
                blockAttrs = listAttrs(indent: 14, type: .bulletItem, dark: dark); prefix = "• "
            case .numberedItem:
                blockAttrs = listAttrs(indent: 24, type: .numberedItem, dark: dark); prefix = "\(nIdx). "
            case .taskItem:
                blockAttrs = taskAttrs(checked: b.checked, dark: dark)
                prefix = b.checked ? "☑ " : "☐ "
            case .quote:
                blockAttrs = quoteAttrs(dark: dark); prefix = ""
            case .heading:
                blockAttrs = headingAttrs(level: b.level, dark: dark); prefix = ""
            default:
                blockAttrs = paraAttrs(dark); prefix = ""
            }

            let out = NSMutableAttributedString()
            if !prefix.isEmpty {
                out.append(NSAttributedString(string: prefix, attributes: blockAttrs))
            }
            let baseFont = (blockAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            for span in b.spans.isEmpty ? [TextSpan("")] : b.spans {
                out.append(attributedSpan(span, blockAttrs: blockAttrs, baseFont: baseFont))
            }
            return out
        }

        private func attributedSpan(_ span: TextSpan, blockAttrs: [NSAttributedString.Key: Any], baseFont: NSFont) -> NSAttributedString {
            var attrs = blockAttrs
            attrs[.font] = spanFont(span, base: baseFont)
            if span.underline     { attrs[.underlineStyle]     = NSUnderlineStyle.single.rawValue }
            if span.strikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if span.highlight     { attrs[.backgroundColor]    = NSColor.yellow.withAlphaComponent(0.35) }
            if span.code          { attrs[.backgroundColor]    = NSColor(white: 1, alpha: 0.07) }
            return NSAttributedString(string: span.text, attributes: attrs)
        }

        private func spanFont(_ span: TextSpan, base: NSFont) -> NSFont {
            if span.code { return NSFont.monospacedSystemFont(ofSize: base.pointSize - 1, weight: .regular) }
            var traits = base.fontDescriptor.symbolicTraits
            if span.bold   { traits.insert(.bold) }
            if span.italic { traits.insert(.italic) }
            guard traits != base.fontDescriptor.symbolicTraits else { return base }
            let desc = base.fontDescriptor.withSymbolicTraits(traits)
            return NSFont(descriptor: desc, size: base.pointSize) ?? base
        }

        private func toggleFontTrait(_ trait: NSFontDescriptor.SymbolicTraits, on font: NSFont, remove: Bool) -> NSFont {
            var traits = font.fontDescriptor.symbolicTraits
            if remove { traits.remove(trait) } else { traits.insert(trait) }
            let desc = font.fontDescriptor.withSymbolicTraits(traits)
            return NSFont(descriptor: desc, size: font.pointSize) ?? font
        }

        // MARK: Display string (used only for change detection)

        func displayString(for blocks: [Block]) -> String {
            var n = 1
            return blocks.map { b -> String in
                switch b.type {
                case .bulletItem:
                    n = 1
                    return "• \(b.plainText)"
                case .numberedItem:
                    defer { n += 1 }
                    return "\(n). \(b.plainText)"
                case .taskItem:
                    n = 1
                    return "\(b.checked ? "☑" : "☐") \(b.plainText)"
                case .divider:
                    n = 1
                    return "─────────────────────"
                case .image:
                    n = 1
                    return b.imageAlt.isEmpty ? " " : b.imageAlt
                default:
                    n = 1
                    return b.plainText
                }
            }.joined(separator: "\n")
        }

        // MARK: Line + attributes per block

        func lineAndAttrs(_ b: Block, nIdx: Int, dark: Bool) -> (String, [NSAttributedString.Key: Any]) {
            let content = b.plainText
            switch b.type {
            case .paragraph:
                return (content, paraAttrs(dark))
            case .heading:
                return (content, headingAttrs(level: b.level, dark: dark))
            case .bulletItem:
                return ("• \(content)", listAttrs(indent: 14, type: .bulletItem, dark: dark))
            case .numberedItem:
                return ("\(nIdx). \(content)", listAttrs(indent: 24, type: .numberedItem, dark: dark))
            case .taskItem:
                return ("\(b.checked ? "☑" : "☐") \(content)", taskAttrs(checked: b.checked, dark: dark))
            case .quote:
                return (content, quoteAttrs(dark: dark))
            case .divider:
                return ("─────────────────────", dividerAttrs(dark: dark))
            case .image:
                let placeholder = b.imageAlt.isEmpty ? " " : b.imageAlt
                var attrs = paraAttrs(dark)
                if let url = b.imageURL { attrs[kJBImageURL] = url }
                attrs[kJBType] = BlockType.image.rawValue
                return (placeholder, attrs)
            default:
                return (b.plainText, paraAttrs(dark))
            }
        }

        // MARK: Extract blocks from storage

        func extractBlocks(from storage: NSTextStorage) -> [Block] {
            let str = storage.string as NSString
            var result: [Block] = []
            var loc = 0
            while loc < storage.length {
                let pr = str.paragraphRange(for: NSRange(location: loc, length: 0))
                let hasNL = pr.length > 0 && str.character(at: pr.location + pr.length - 1) == 10
                let lineNSRange = NSRange(location: pr.location, length: pr.length - (hasNL ? 1 : 0))
                let line = str.substring(with: lineNSRange)

                let blockAttrs = safeAttributes(in: storage, at: pr.location)
                let typeRaw  = blockAttrs[kJBType]    as? String ?? BlockType.paragraph.rawValue
                let btype    = BlockType(rawValue: typeRaw) ?? .paragraph
                let level    = blockAttrs[kJBLevel]   as? Int  ?? 1
                let checked  = blockAttrs[kJBChecked] as? Bool ?? false
                let imageURL = blockAttrs[kJBImageURL] as? String
                let baseFont = (blockAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 14)

                if btype == .divider {
                    result.append(Block(type: .divider))
                } else if btype == .image {
                    result.append(Block(type: .image, imageURL: imageURL, imageAlt: line))
                } else {
                    let prefixLen = structuralPrefixLen(for: btype, in: line)
                    let contentStart = lineNSRange.location + prefixLen
                    let contentLen   = max(0, lineNSRange.length - prefixLen)
                    let contentRange = NSRange(location: contentStart, length: contentLen)
                    let isCheckedLine = line.hasPrefix("☑ ")
                    let spans = contentRange.length > 0
                        ? spansFromStorage(storage, range: contentRange, baseFont: baseFont, isChecked: checked)
                        : [TextSpan("")]
                    switch btype {
                    case .taskItem: result.append(Block(type: .taskItem, spans: spans, checked: isCheckedLine || checked))
                    case .heading:  result.append(Block(type: .heading,  spans: spans, level: max(1, min(level, 3))))
                    default:        result.append(Block(type: btype, spans: spans))
                    }
                }
                loc = NSMaxRange(pr)
            }
            return result.isEmpty ? [Block(type: .paragraph, spans: [TextSpan("")])] : result
        }

        private func structuralPrefixLen(for type: BlockType, in line: String) -> Int {
            switch type {
            case .bulletItem: return line.hasPrefix("• ") ? 2 : 0
            case .numberedItem:
                if let r = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                    return line.distance(from: line.startIndex, to: r.upperBound)
                }
                return 0
            case .taskItem: return (line.hasPrefix("☑ ") || line.hasPrefix("☐ ")) ? 2 : 0
            default: return 0
            }
        }

        private func spansFromStorage(_ storage: NSTextStorage, range: NSRange, baseFont: NSFont, isChecked: Bool) -> [TextSpan] {
            let baseTraits = baseFont.fontDescriptor.symbolicTraits
            var spans: [TextSpan] = []
            storage.enumerateAttributes(in: range, options: []) { attrs, r, _ in
                let text = (storage.string as NSString).substring(with: r)
                var span = TextSpan(text)
                if let font = attrs[.font] as? NSFont {
                    let traits = font.fontDescriptor.symbolicTraits
                    span.bold   = traits.contains(.bold)   && !baseTraits.contains(.bold)
                    span.italic = traits.contains(.italic) && !baseTraits.contains(.italic)
                    span.code   = font.isFixedPitch && !baseFont.isFixedPitch
                }
                // obliqueness used by legacy italic path
                if let obl = attrs[.obliqueness] as? NSNumber, obl.floatValue > 0 { span.italic = true }
                if let u = attrs[.underlineStyle]     as? Int, u != 0 { span.underline     = true }
                if !isChecked, let s = attrs[.strikethroughStyle] as? Int, s != 0 { span.strikethrough = true }
                if !span.code, attrs[.backgroundColor] != nil          { span.highlight    = true }
                spans.append(span)
            }
            return spans.isEmpty ? [TextSpan("")] : spans
        }

        func blockFromDisplayedLine(_ line: String, type: BlockType, level: Int, checked: Bool, imageURL: String? = nil) -> Block {
            switch type {
            case .heading:
                let t = line.hasPrefix("# ") ? String(line.dropFirst(2)) : line
                return Block(type: .heading, spans: Block.parseInlineMarkdown(t), level: max(1, min(level, 3)))
            case .bulletItem:
                let t = line.hasPrefix("• ") ? String(line.dropFirst(2)) : line
                return Block(type: .bulletItem, spans: Block.parseInlineMarkdown(t))
            case .numberedItem:
                let t: String
                if let r = line.range(of: #"^\d+\. "#, options: .regularExpression) { t = String(line[r.upperBound...]) } else { t = line }
                return Block(type: .numberedItem, spans: Block.parseInlineMarkdown(t))
            case .taskItem:
                let isChecked = line.hasPrefix("☑ ")
                let t = (line.hasPrefix("☑ ") || line.hasPrefix("☐ ")) ? String(line.dropFirst(2)) : line
                return Block(type: .taskItem, spans: Block.parseInlineMarkdown(t), checked: isChecked || checked)
            case .quote:
                let t = line.hasPrefix("❝ ") ? String(line.dropFirst(2)) : line
                return Block(type: .quote, spans: Block.parseInlineMarkdown(t))
            case .divider:
                return Block(type: .divider)
            case .image:
                return Block(type: .image, imageURL: imageURL, imageAlt: line)
            default:
                return Block(type: .paragraph, spans: Block.parseInlineMarkdown(line))
            }
        }

        // MARK: Attribute factories

        func paraAttrs(_ dark: Bool) -> [NSAttributedString.Key: Any] {
            let ps = NSMutableParagraphStyle(); ps.lineSpacing = 3
            return [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: textColor(dark, 0.88),
                    .paragraphStyle: ps, kJBType: BlockType.paragraph.rawValue]
        }

        func headingAttrs(level: Int, dark: Bool) -> [NSAttributedString.Key: Any] {
            let sz: CGFloat = level == 1 ? 20 : level == 2 ? 17 : 15
            let wt: NSFont.Weight = level == 1 ? .bold : .semibold
            let ps = NSMutableParagraphStyle(); ps.lineSpacing = 2; ps.paragraphSpacingBefore = level == 1 ? 6 : 3
            return [.font: NSFont.systemFont(ofSize: sz, weight: wt), .foregroundColor: textColor(dark, 0.92),
                    .paragraphStyle: ps, kJBType: BlockType.heading.rawValue, kJBLevel: level]
        }

        func listAttrs(indent: CGFloat, type: BlockType, dark: Bool) -> [NSAttributedString.Key: Any] {
            let ps = NSMutableParagraphStyle(); ps.headIndent = indent; ps.firstLineHeadIndent = 0; ps.lineSpacing = 3
            return [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: textColor(dark, 0.88),
                    .paragraphStyle: ps, kJBType: type.rawValue]
        }

        func taskAttrs(checked: Bool, dark: Bool) -> [NSAttributedString.Key: Any] {
            let alpha: CGFloat = checked ? 0.38 : 0.88
            let ps = NSMutableParagraphStyle(); ps.headIndent = 16; ps.lineSpacing = 3
            var a: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: textColor(dark, alpha),
                .paragraphStyle: ps, kJBType: BlockType.taskItem.rawValue, kJBChecked: checked
            ]
            if checked { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            return a
        }

        func quoteAttrs(dark: Bool) -> [NSAttributedString.Key: Any] {
            let ps = NSMutableParagraphStyle(); ps.headIndent = 12; ps.firstLineHeadIndent = 12; ps.lineSpacing = 3
            let italicFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14), toHaveTrait: .italicFontMask)
            return [.font: italicFont, .foregroundColor: textColor(dark, 0.52),
                    .paragraphStyle: ps, kJBType: BlockType.quote.rawValue]
        }

        func dividerAttrs(dark: Bool) -> [NSAttributedString.Key: Any] {
            let ps = NSMutableParagraphStyle(); ps.lineSpacing = 6; ps.paragraphSpacingBefore = 4
            return [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: textColor(dark, 0.25),
                    .paragraphStyle: ps, kJBType: BlockType.divider.rawValue]
        }

        func textColor(_ dark: Bool, _ alpha: CGFloat) -> NSColor {
            dark ? NSColor.white.withAlphaComponent(alpha) : NSColor.black.withAlphaComponent(alpha)
        }

        func updateTypingAttrs(_ tv: NSTextView) {
            guard let storage = tv.textStorage, storage.length > 0 else {
                tv.typingAttributes = paraAttrs(parent.isDark); return
            }
            let loc = tv.selectedRange().location
            if isTrailingEmptyParagraph(cursor: loc, storage: storage) {
                tv.typingAttributes = paraAttrs(parent.isDark)
                return
            }
            // When cursor is past end of storage (e.g. just inserted newline at end),
            // there's no character to read from — leave typingAttributes as already set.
            guard loc < storage.length else { return }
            let keep: Set<NSAttributedString.Key> = [.font, .foregroundColor, .paragraphStyle,
                                                       .strikethroughStyle, kJBType, kJBLevel, kJBChecked]
            let ta = storage.attributes(at: loc, effectiveRange: nil).filter { keep.contains($0.key) }
            tv.typingAttributes = ta
        }

        // MARK: Toolbar formatting

        func applyFormat(_ command: JottTextFormatCommand, in tv: NSTextView) -> Bool {
            switch command {
            // ── Paragraph-level (toggle: same type → revert to paragraph) ──
            case .bulletList:
                if currentBlockType(in: tv) == .bulletItem {
                    applyParagraphFormat(prefix: "", attrs: paraAttrs(parent.isDark), in: tv, clearPrefix: "• ")
                } else {
                    applyParagraphFormat(prefix: "• ", attrs: listAttrs(indent: 14, type: .bulletItem, dark: parent.isDark), in: tv)
                }
                return true
            case .numberedList:
                if currentBlockType(in: tv) == .numberedItem {
                    applyParagraphFormat(prefix: "", attrs: paraAttrs(parent.isDark), in: tv, clearPrefix: nil)
                } else {
                    applyParagraphFormat(prefix: "1. ", attrs: listAttrs(indent: 24, type: .numberedItem, dark: parent.isDark), in: tv)
                    renumber(in: tv)
                }
                return true
            case .taskList:
                if currentBlockType(in: tv) == .taskItem {
                    applyParagraphFormat(prefix: "", attrs: paraAttrs(parent.isDark), in: tv, clearPrefix: nil)
                } else {
                    applyParagraphFormat(prefix: "☐ ", attrs: taskAttrs(checked: false, dark: parent.isDark), in: tv)
                }
                return true
            case .quote:
                if currentBlockType(in: tv) == .quote {
                    applyParagraphFormat(prefix: "", attrs: paraAttrs(parent.isDark), in: tv, clearPrefix: nil)
                } else {
                    applyParagraphFormat(prefix: "", attrs: quoteAttrs(dark: parent.isDark), in: tv)
                }
                return true
            case .heading:
                if currentBlockType(in: tv) == .heading {
                    applyParagraphFormat(prefix: "", attrs: paraAttrs(parent.isDark), in: tv, clearPrefix: nil)
                } else {
                    applyParagraphFormat(prefix: "", attrs: headingAttrs(level: 1, dark: parent.isDark), in: tv)
                }
                return true

            // ── Inline / character-level (toggle on/off over selection) ──
            case .bold:          applyInlineFormat(.bold, in: tv);          return true
            case .italic:        applyInlineFormat(.italic, in: tv);        return true
            case .underline:     applyInlineFormat(.underline, in: tv);     return true
            case .strikethrough: applyInlineFormat(.strikethrough, in: tv); return true
            case .inlineCode:    applyInlineFormat(.inlineCode, in: tv);    return true
            case .link:          applyInlineFormat(.link, in: tv);          return true

            default:
                return false
            }
        }

        // ── Which attribute key / value pairs represent the given inline format ──
        private func inlineFormatAttrs(_ cmd: JottTextFormatCommand) -> [NSAttributedString.Key: Any] {
            switch cmd {
            case .bold:
                return [.font: NSFont.systemFont(ofSize: 14, weight: .bold)]
            case .italic:
                return [.obliqueness: 0.25 as NSNumber]
            case .underline:
                return [.underlineStyle: NSUnderlineStyle.single.rawValue as NSNumber]
            case .strikethrough:
                return [.strikethroughStyle: NSUnderlineStyle.single.rawValue as NSNumber]
            case .inlineCode:
                let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                let bg = NSColor(white: 1, alpha: 0.07)
                return [.font: codeFont, .backgroundColor: bg]
            case .link:
                return [.underlineStyle: NSUnderlineStyle.single.rawValue as NSNumber,
                        .foregroundColor: NSColor.systemBlue]
            default:
                return [:]
            }
        }

        private func isInlineActive(_ cmd: JottTextFormatCommand, in tv: NSTextView) -> Bool {
            guard let storage = tv.textStorage else { return false }
            let sel = stableSelectedRange(in: tv)
            // For zero-length selection check typing attributes
            let checkRange = sel.length == 0
                ? (sel.location > 0 ? NSRange(location: sel.location - 1, length: 1) : sel)
                : sel
            guard checkRange.location + checkRange.length <= storage.length else { return false }
            let attrs = storage.attributes(at: checkRange.location, effectiveRange: nil)
            switch cmd {
            case .bold:
                return (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            case .italic:
                return (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
                    || (attrs[.obliqueness] as? NSNumber)?.floatValue ?? 0 > 0
            case .underline:
                return (attrs[.underlineStyle] as? NSNumber)?.intValue ?? 0 != 0
            case .strikethrough:
                return (attrs[.strikethroughStyle] as? NSNumber)?.intValue ?? 0 != 0
            case .inlineCode:
                return (attrs[.font] as? NSFont)?.isFixedPitch ?? false
            default: return false
            }
        }

        func applyInlineFormat(_ cmd: JottTextFormatCommand, in tv: NSTextView) {
            guard let storage = tv.textStorage else { return }

            if cmd == .link {
                let sel = stableSelectedRange(in: tv)
                let selected = sel.length > 0 ? (tv.string as NSString).substring(with: sel) : ""
                let replacement = sel.length > 0 ? "[\(selected)](url)" : "[](url)"
                tv.insertText(replacement, replacementRange: sel)
                tv.setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                suppressSync = true
                let newBlocks = extractBlocks(from: storage)
                if parent.blocks != newBlocks { parent.blocks = newBlocks }
                suppressSync = false
                return
            }

            let sel = stableSelectedRange(in: tv)
            guard sel.length > 0 else { return }

            // Snapshot attributes before change so Cmd+Z can restore them
            let snapshot = storage.attributedSubstring(from: sel)
            tv.undoManager?.registerUndo(withTarget: storage) { [weak tv, snapshot] _ in
                guard let tv, let storage = tv.textStorage else { return }
                storage.beginEditing()
                storage.replaceCharacters(in: sel, with: snapshot)
                storage.endEditing()
                tv.setSelectedRange(sel)
            }
            tv.undoManager?.setActionName("Formatting")

            let isActive = isInlineActive(cmd, in: tv)
            storage.beginEditing()
            storage.enumerateAttributes(in: sel, options: []) { attrs, r, _ in
                let baseFont = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 14)
                switch cmd {
                case .bold:
                    storage.addAttribute(.font, value: toggleFontTrait(.bold, on: baseFont, remove: isActive), range: r)
                case .italic:
                    storage.addAttribute(.font, value: toggleFontTrait(.italic, on: baseFont, remove: isActive), range: r)
                    storage.removeAttribute(.obliqueness, range: r)
                case .underline:
                    if isActive { storage.removeAttribute(.underlineStyle, range: r) }
                    else { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
                case .strikethrough:
                    if isActive { storage.removeAttribute(.strikethroughStyle, range: r) }
                    else { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
                case .highlight:
                    if isActive { storage.removeAttribute(.backgroundColor, range: r) }
                    else { storage.addAttribute(.backgroundColor, value: NSColor.yellow.withAlphaComponent(0.35), range: r) }
                case .inlineCode:
                    if isActive {
                        let restored = toggleFontTrait(.monoSpace, on: baseFont, remove: true)
                        storage.addAttribute(.font, value: restored, range: r)
                        storage.removeAttribute(.backgroundColor, range: r)
                    } else {
                        let codeFont = NSFont.monospacedSystemFont(ofSize: max(baseFont.pointSize - 1, 11), weight: .regular)
                        storage.addAttribute(.font, value: codeFont, range: r)
                        storage.addAttribute(.backgroundColor, value: NSColor(white: 1, alpha: 0.07), range: r)
                    }
                default: break
                }
            }
            storage.endEditing()
            tv.setSelectedRange(sel)

            suppressSync = true
            let newBlocks = extractBlocks(from: storage)
            if parent.blocks != newBlocks { parent.blocks = newBlocks }
            suppressSync = false
        }

        /// Returns the BlockType of the paragraph at the current cursor
        func currentBlockType(in tv: NSTextView) -> BlockType {
            guard let storage = tv.textStorage else { return .paragraph }
            let sel = stableSelectedRange(in: tv)
            let loc = min(sel.location, max(0, storage.length - 1))
            guard storage.length > 0 else { return .paragraph }
            let attrs = safeAttributes(in: storage, at: loc)
            let raw = attrs[kJBType] as? String ?? BlockType.paragraph.rawValue
            return BlockType(rawValue: raw) ?? .paragraph
        }


        func applyParagraphFormat(prefix: String, attrs: [NSAttributedString.Key: Any], in tv: NSTextView, clearPrefix: String? = nil) {
            guard let storage = tv.textStorage else { return }
            let selected = stableSelectedRange(in: tv)
            tv.setSelectedRange(selected)

            if selected.length == 0,
               selected.location == storage.length,
               storage.string.hasSuffix("\n") {
                storage.beginEditing()
                storage.replaceCharacters(in: selected, with: prefix)
                if !prefix.isEmpty {
                    storage.setAttributes(attrs, range: NSRange(location: selected.location, length: (prefix as NSString).length))
                }
                storage.endEditing()
                let cursor = selected.location + (prefix as NSString).length
                tv.setSelectedRange(NSRange(location: cursor, length: 0))
                if let libraryTextView = tv as? JottLibraryTextView {
                    libraryTextView.lastKnownSelectedRange = tv.selectedRange()
                }
                tv.typingAttributes = attrs
                tv.didChangeText()
                return
            }

            let ns = storage.string as NSString
            let safeLocation = min(selected.location, storage.length)
            let targetRange = ns.paragraphRange(for: NSRange(location: safeLocation, length: selected.length))
            var starts: [Int] = []

            if targetRange.length == 0 {
                starts = [targetRange.location]
            } else {
                var loc = targetRange.location
                while loc < NSMaxRange(targetRange) {
                    starts.append(loc)
                    let pr = (storage.string as NSString).paragraphRange(for: NSRange(location: loc, length: 0))
                    let next = NSMaxRange(pr)
                    loc = next > loc ? next : loc + 1
                }
            }

            storage.beginEditing()
            for start in starts.reversed() {
                let currentString = storage.string as NSString
                let clampedStart = min(start, currentString.length)
                let pr = currentString.paragraphRange(for: NSRange(location: clampedStart, length: 0))
                let hasNL = pr.length > 0 && currentString.character(at: pr.location + pr.length - 1) == 10
                let lineRange = NSRange(location: pr.location, length: pr.length - (hasNL ? 1 : 0))
                let line = lineRange.length > 0 ? currentString.substring(with: lineRange) : ""
                let replacement = prefix + strippedBlockPrefix(from: line)
                storage.replaceCharacters(in: lineRange, with: replacement)
                let newPR = (storage.string as NSString).paragraphRange(for: NSRange(location: pr.location, length: 0))
                if newPR.length > 0 {
                    storage.setAttributes(attrs, range: newPR)
                }
            }
            storage.endEditing()

            let cursor = min(selected.location + (prefix as NSString).length, storage.length)
            tv.setSelectedRange(NSRange(location: cursor, length: 0))
            if let libraryTextView = tv as? JottLibraryTextView {
                libraryTextView.lastKnownSelectedRange = tv.selectedRange()
            }
            tv.typingAttributes = attrs
            tv.didChangeText()
        }

        func stableSelectedRange(in tv: NSTextView) -> NSRange {
            let current = tv.selectedRange()
            let stored = (tv as? JottLibraryTextView)?.lastKnownSelectedRange ?? current
            let candidate = current.location == 0 && stored.location > 0 ? stored : current
            let length = tv.textStorage?.length ?? tv.string.utf16.count
            let location = min(max(candidate.location, 0), length)
            let selectionLength = min(max(candidate.length, 0), max(0, length - location))
            return NSRange(location: location, length: selectionLength)
        }

        func strippedBlockPrefix(from line: String) -> String {
            var text = line
            for prefix in ["• ", "☐ ", "☑ "] where text.hasPrefix(prefix) {
                return String(text.dropFirst(prefix.count))
            }
            let patterns = [
                #"^\d+\. "#,
                #"^[-*+] "#,
                #"^- \[[ xX]\] "#,
                #"^#{1,6}\s+"#,
                #"^>\s?"#
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let ns = text as NSString
                let range = NSRange(location: 0, length: ns.length)
                if let match = regex.firstMatch(in: text, range: range), match.range.location == 0 {
                    text = ns.substring(from: match.range.length)
                    break
                }
            }
            return text
        }

        // MARK: NSTextViewDelegate

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv else { return }
            if let libraryTextView = tv as? JottLibraryTextView {
                libraryTextView.lastKnownSelectedRange = tv.selectedRange()
            }
            updateTypingAttrs(tv)
        }

        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange, replacementString repl: String?) -> Bool {
            guard let repl, repl == " ", range.length == 0 else { return true }
            return !handleSpaceTrigger(in: tv, at: range.location)
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:))  { return handleEnter(in: tv) }
            // Backspace on empty field — clear command/forced mode (fallback when performKeyEquivalent misses it)
            if sel == #selector(NSResponder.deleteBackward(_:)),
               (tv.string.isEmpty || tv.string == "\n") {
                parent.onBackspaceOnEmpty?()
                return true
            }
            if sel == #selector(NSResponder.deleteBackward(_:)) { return handleBackspace(in: tv) }
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView ?? tv, let storage = tv.textStorage else { return }
            if let libraryTextView = tv as? JottLibraryTextView {
                libraryTextView.lastKnownSelectedRange = tv.selectedRange()
            }
            suppressSync = true
            let newBlocks = extractBlocks(from: storage)
            if parent.blocks != newBlocks { parent.blocks = newBlocks }
            updateTypingAttrs(tv)
            reportHeight(from: tv)
            suppressSync = false
        }

        // MARK: Space trigger

        func handleSpaceTrigger(in tv: NSTextView, at cursor: Int) -> Bool {
            guard let storage = tv.textStorage else { return false }
            let str = storage.string as NSString
            let pr = str.paragraphRange(for: NSRange(location: cursor, length: 0))
            let before = cursor > pr.location
                ? str.substring(with: NSRange(location: pr.location, length: cursor - pr.location))
                : ""

            switch before {
            case "-", "*", "+":
                trigger(.bulletItem, level: 1, lineStart: pr.location, trigLen: before.utf16.count, prefix: "• ", dark: parent.isDark, in: tv)
                return true
            case "#":
                trigger(.heading, level: 1, lineStart: pr.location, trigLen: 1, prefix: "", dark: parent.isDark, in: tv)
                return true
            case "##":
                trigger(.heading, level: 2, lineStart: pr.location, trigLen: 2, prefix: "", dark: parent.isDark, in: tv)
                return true
            case "###":
                trigger(.heading, level: 3, lineStart: pr.location, trigLen: 3, prefix: "", dark: parent.isDark, in: tv)
                return true
            case ">":
                trigger(.quote, level: 1, lineStart: pr.location, trigLen: 1, prefix: "", dark: parent.isDark, in: tv)
                return true
            case "[]", "[ ]":
                trigger(.taskItem, level: 1, lineStart: pr.location, trigLen: before.utf16.count, prefix: "☐ ", dark: parent.isDark, in: tv)
                return true
            case "[x]", "[X]":
                trigger(.taskItem, level: 1, lineStart: pr.location, trigLen: before.utf16.count, prefix: "☑ ", dark: parent.isDark, in: tv, checked: true)
                return true
            default:
                if before.range(of: #"^\d+\.$"#, options: .regularExpression) != nil {
                    let num = String(before.dropLast())
                    trigger(.numberedItem, level: 1, lineStart: pr.location, trigLen: before.utf16.count, prefix: "\(num). ", dark: parent.isDark, in: tv)
                    return true
                }
                return false
            }
        }

        func trigger(_ type: BlockType, level: Int, lineStart: Int, trigLen: Int, prefix: String, dark: Bool, in tv: NSTextView, checked: Bool = false) {
            guard let storage = tv.textStorage else { return }
            var attrs: [NSAttributedString.Key: Any]
            switch type {
            case .bulletItem:   attrs = listAttrs(indent: 14, type: .bulletItem, dark: dark)
            case .numberedItem: attrs = listAttrs(indent: 24, type: .numberedItem, dark: dark)
            case .heading:      attrs = headingAttrs(level: level, dark: dark)
            case .taskItem:     attrs = taskAttrs(checked: checked, dark: dark)
            case .quote:        attrs = quoteAttrs(dark: dark)
            default:            attrs = paraAttrs(dark)
            }
            storage.beginEditing()
            storage.replaceCharacters(in: NSRange(location: lineStart, length: trigLen), with: prefix)
            let newPR = (storage.string as NSString).paragraphRange(for: NSRange(location: lineStart, length: 0))
            storage.setAttributes(attrs, range: newPR)
            storage.endEditing()
            let cur = lineStart + (prefix as NSString).length
            tv.setSelectedRange(NSRange(location: cur, length: 0))
            tv.typingAttributes = attrs
            tv.didChangeText()
        }

        // MARK: Enter

        func handleEnter(in tv: NSTextView) -> Bool {
            guard tv.selectedRange().length == 0, let storage = tv.textStorage else { return false }
            let cursor = tv.selectedRange().location
            let str = storage.string as NSString
            let pr = str.paragraphRange(for: NSRange(location: cursor, length: 0))
            let before = cursor > pr.location
                ? str.substring(with: NSRange(location: pr.location, length: cursor - pr.location))
                : ""
            let attrs = currentParagraphAttributes(in: storage, paragraphLocation: pr.location, cursor: cursor)
            let btype = BlockType(rawValue: attrs[kJBType] as? String ?? "") ?? .paragraph

            switch btype {
            case .bulletItem:
                let content = before.hasPrefix("• ") ? String(before.dropFirst(2)) : before
                if content.trimmingCharacters(in: .whitespaces).isEmpty {
                    exitList(lineStart: pr.location, prefixLen: min(2, before.utf16.count), in: tv); return true
                }
                continueLine(prefix: "• ", attrs: attrs, in: tv); return true

            case .numberedItem:
                let (num, pLen) = parseNumPrefix(before)
                let content = pLen < before.utf16.count ? (before as NSString).substring(from: pLen) : ""
                if content.trimmingCharacters(in: .whitespaces).isEmpty && !before.isEmpty {
                    exitList(lineStart: pr.location, prefixLen: pLen, in: tv); return true
                }
                continueLine(prefix: "\(num + 1). ", attrs: attrs, in: tv)
                renumber(in: tv); return true

            case .taskItem:
                let pfx = before.hasPrefix("☑ ") || before.hasPrefix("☐ ") ? 2 : 0
                let content = pfx > 0 ? String(before.dropFirst(pfx)) : before
                if content.trimmingCharacters(in: .whitespaces).isEmpty {
                    exitList(lineStart: pr.location, prefixLen: pfx, in: tv); return true
                }
                let newA = taskAttrs(checked: false, dark: parent.isDark)
                continueLine(prefix: "☐ ", attrs: newA, in: tv); return true

            case .heading:
                continueLine(prefix: "", attrs: paraAttrs(parent.isDark), in: tv, overrideType: true); return true

            case .quote:
                if before.trimmingCharacters(in: .whitespaces).isEmpty {
                    exitList(lineStart: pr.location, prefixLen: 0, in: tv); return true
                }
                continueLine(prefix: "", attrs: attrs, in: tv); return true

            default: return false
            }
        }

        func continueLine(prefix: String, attrs: [NSAttributedString.Key: Any], in tv: NSTextView, overrideType: Bool = false) {
            guard let storage = tv.textStorage else { return }
            let resolvedAttrs = overrideType ? paraAttrs(parent.isDark) : attrs
            let insertionRange = tv.selectedRange()
            let inserted = "\n\(prefix)" as NSString
            // Use storage editing directly so we can set attributes atomically before
            // textDidChange fires. tv.insertText would fire textViewDidChangeSelection
            // mid-edit before setAttributes, giving extractBlocks the wrong block type.
            storage.beginEditing()
            storage.replaceCharacters(in: insertionRange, with: inserted as String)
            let newCursor = insertionRange.location + inserted.length
            let newParaLoc = newCursor - (prefix as NSString).length
            let newPR = (storage.string as NSString).paragraphRange(for: NSRange(location: newParaLoc, length: 0))
            storage.setAttributes(resolvedAttrs, range: newPR)
            storage.endEditing()
            tv.setSelectedRange(NSRange(location: newCursor, length: 0))
            if let libraryTextView = tv as? JottLibraryTextView {
                libraryTextView.lastKnownSelectedRange = tv.selectedRange()
            }
            tv.typingAttributes = resolvedAttrs
            tv.didChangeText()
        }

        func exitList(lineStart: Int, prefixLen: Int, in tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let pa = paraAttrs(parent.isDark)
            storage.beginEditing()
            if prefixLen > 0 { storage.replaceCharacters(in: NSRange(location: lineStart, length: prefixLen), with: "") }
            let newPR = (storage.string as NSString).paragraphRange(for: NSRange(location: lineStart, length: 0))
            storage.setAttributes(pa, range: newPR)
            storage.endEditing()
            tv.setSelectedRange(NSRange(location: lineStart, length: 0))
            if let libraryTextView = tv as? JottLibraryTextView {
                libraryTextView.lastKnownSelectedRange = tv.selectedRange()
            }
            tv.typingAttributes = pa
            tv.didChangeText()
        }

        // MARK: Backspace

        func handleBackspace(in tv: NSTextView) -> Bool {
            guard tv.selectedRange().length == 0, let storage = tv.textStorage else { return false }
            let cursor = tv.selectedRange().location
            let str = storage.string as NSString
            let pr = str.paragraphRange(for: NSRange(location: cursor, length: 0))
            let before = cursor > pr.location
                ? str.substring(with: NSRange(location: pr.location, length: cursor - pr.location))
                : ""
            let btype = BlockType(rawValue: currentParagraphAttributes(in: storage, paragraphLocation: pr.location, cursor: cursor)[kJBType] as? String ?? "") ?? .paragraph

            let hasNLAtEnd = pr.length > 0 && str.character(at: NSMaxRange(pr) - 1) == 10
            let lineTextEnd = NSMaxRange(pr) - (hasNLAtEnd ? 1 : 0)
            let cursorAtLineEnd = cursor >= lineTextEnd

            switch btype {
            case .bulletItem where before == "• ":
                // Only exit the list when there is no content after the cursor on this line.
                if cursorAtLineEnd { exitList(lineStart: pr.location, prefixLen: 2, in: tv); return true }
            case .taskItem where before == "☐ " || before == "☑ ":
                if cursorAtLineEnd { exitList(lineStart: pr.location, prefixLen: 2, in: tv); return true }
            case .heading where cursor == pr.location:
                exitList(lineStart: pr.location, prefixLen: 0, in: tv); return true
            case .quote where cursor == pr.location:
                exitList(lineStart: pr.location, prefixLen: 0, in: tv); return true
            case .numberedItem:
                let (_, pLen) = parseNumPrefix(before)
                if before.utf16.count == pLen && cursorAtLineEnd {
                    exitList(lineStart: pr.location, prefixLen: pLen, in: tv); return true
                }
            default: break
            }
            return false
        }

        // MARK: Helpers

        func parseNumPrefix(_ text: String) -> (Int, Int) {
            let ns = text as NSString
            guard let m = try? NSRegularExpression(pattern: #"^(\d+)\. "#)
                .firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return (1, 0) }
            return (Int(ns.substring(with: m.range(at: 1))) ?? 1, m.range.length)
        }

        func renumber(in tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            var edits: [(NSRange, String)] = []
            var n = 1
            var loc = 0
            while loc < storage.length {
                let pr = (storage.string as NSString).paragraphRange(for: NSRange(location: loc, length: 0))
                let hasNL = pr.length > 0 && (storage.string as NSString).character(at: pr.location + pr.length - 1) == 10
                let lr = NSRange(location: pr.location, length: pr.length - (hasNL ? 1 : 0))
                let line = (storage.string as NSString).substring(with: lr)
                let attrs = safeAttributes(in: storage, at: pr.location)
                if BlockType(rawValue: attrs[kJBType] as? String ?? "") == .numberedItem {
                    let (_, pLen) = parseNumPrefix(line)
                    let content = pLen < line.utf16.count ? (line as NSString).substring(from: pLen) : ""
                    let want = "\(n). \(content)"
                    if line != want { edits.append((lr, want)) }
                    n += 1
                } else { n = 1 }
                loc = NSMaxRange(pr)
            }
            guard !edits.isEmpty else { return }
            storage.beginEditing()
            for (r, s) in edits.reversed() { storage.replaceCharacters(in: r, with: s) }
            storage.endEditing()
            tv.didChangeText()
        }

        func isTrailingEmptyParagraph(cursor: Int, storage: NSTextStorage) -> Bool {
            cursor == storage.length && storage.length > 0 && storage.string.hasSuffix("\n")
        }

        func currentParagraphAttributes(in storage: NSTextStorage, paragraphLocation: Int, cursor: Int) -> [NSAttributedString.Key: Any] {
            if isTrailingEmptyParagraph(cursor: cursor, storage: storage) {
                return paraAttrs(parent.isDark)
            }
            return safeAttributes(in: storage, at: paragraphLocation)
        }

        func safeAttributes(in storage: NSTextStorage, at location: Int) -> [NSAttributedString.Key: Any] {
            guard storage.length > 0 else { return paraAttrs(parent.isDark) }
            let safeLocation = min(max(location, 0), storage.length - 1)
            return storage.attributes(at: safeLocation, effectiveRange: nil)
        }
    }
}


private struct LibraryReminderInspector: View {
    let reminder: Reminder
    let isDarkMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reminder")
                .font(JottTypography.title(17, weight: .semibold))
                .foregroundColor(.primary)

            Text(reminder.text)
                .font(JottTypography.title(21, weight: .semibold))
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                Text(formattedDueDate(reminder.dueDate))
                    .font(JottTypography.ui(12, weight: .medium))
            }
            .foregroundColor(.secondary)

            Text(reminder.isCompleted ? "Completed" : "Pending")
                .font(JottTypography.ui(11, weight: .semibold))
                .foregroundColor(reminder.isCompleted ? .green : .jottOverlayPeachAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill((reminder.isCompleted ? Color.green : Color.jottOverlayPeachAccent).opacity(isDarkMode ? 0.16 : 0.12))
                )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func formattedDueDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

extension Calendar {
    func isDateInThisWeek(_ date: Date) -> Bool {
        let weekOfYear = component(.weekOfYear, from: Date())
        let dateWeekOfYear = component(.weekOfYear, from: date)
        return weekOfYear == dateWeekOfYear && component(.year, from: Date()) == component(.year, from: date)
    }
}

#Preview {
    LibraryView(viewModel: OverlayViewModel())
}
