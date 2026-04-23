import SwiftUI
import AppKit

private enum LibraryFilter: Equatable {
    case none
    case pinned
    case tagged(String)
    case today
    case thisWeek
    case thisMonth

    var label: String {
        switch self {
        case .none:          return "All"
        case .pinned:        return "Pinned"
        case .tagged(let t): return "#\(t)"
        case .today:         return "Today"
        case .thisWeek:      return "This week"
        case .thisMonth:     return "This month"
        }
    }
    var isActive: Bool { self != .none }
}

private enum LibraryDisplayMode: String, CaseIterable {
    case grid    = "Grid"
    case list    = "List"
    case folders = "Folders"

    var icon: String {
        switch self {
        case .grid:    return "square.grid.2x2"
        case .list:    return "list.bullet"
        case .folders: return "folder"
        }
    }
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
    @State private var displayMode: LibraryDisplayMode = .grid
    @State private var selectionAnchorNoteID: UUID?
    @State private var isDragSelectingNotes = false
    @State private var isDetailExpanded: Bool = false
    @State private var showDeleteConfirm = false
    @State private var activeFilter: LibraryFilter = .none
    /// Debounced search results — updated async, never on every keystroke.
    @State private var searchResults: [SearchResult] = []
    // Folder navigation
    @State private var activeFolderID: UUID? = nil
    @State private var showNewFolderSheet = false
    @State private var newFolderName: String = ""
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

    private var filteredNotes: [Note] {
        if isSearching {
            return searchResults.compactMap { r in r.isSubnote ? nil : r.note }
        }
        let base = viewModel.getAllNotes().filter { $0.parentId == nil }
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
        return viewModel.getAllNotes().first(where: { $0.id == id })
    }

    private var selectionSyncSignature: String {
        let noteSignature = filteredNotes.map { $0.id.uuidString }.joined(separator: ",")
        return [searchText, displayMode.rawValue, noteSignature]
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
                    displayMode: $displayMode,
                    activeFilter: $activeFilter,
                    visibleCount: filteredItemCount,
                    selectedCount: selectedNoteIDs.count,
                    isDarkMode: isDarkMode,
                    selectedNote: selectedNote,
                    availableTags: availableTags,
                    onDismissDetail: { clearSelection() },
                    onDeleteSelected: { showDeleteConfirm = true }
                )

                Divider()
                    .opacity(isDarkMode ? 0.16 : 0.10)

                ZStack(alignment: .trailing) {
                    // Primary pane always stays full-width (no layout jump)
                    primaryPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(
                            Color.black.opacity(selectedNote != nil && !isDetailExpanded && displayMode != .grid ? 0.18 : 0)
                                .ignoresSafeArea()
                                .allowsHitTesting(false)
                                .animation(.easeInOut(duration: 0.22), value: selectedNote?.id)
                        )
                        .onTapGesture {
                            if selectedNote != nil && !isDetailExpanded && displayMode != .grid { clearSelection() }
                        }

                    // Detail panel — all modes
                    if let note = selectedNote {
                        HStack(spacing: 0) {
                            Divider().opacity(isDarkMode ? 0.14 : 0.09)

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
                        }
                        .frame(maxWidth: isDetailExpanded ? .infinity : 361)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            )
                        )
                        .zIndex(1)
                    }

                }
                .animation(.easeInOut(duration: 0.20), value: selectedNote?.id)
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: isDetailExpanded)
            }
            .background(JottDS(isDark: isDarkMode).canvas)
            .colorScheme(isDarkMode ? .dark : .light)
            .jottAppTypography()
            .task(id: selectionSyncSignature) {
                syncSelection()
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
                        isDark: isDarkMode,
                        onDelete: { deleteSelectedNotes() },
                        onCancel: { showDeleteConfirm = false }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: showDeleteConfirm)
            .onChange(of: displayMode) { _, newMode in
                if newMode != .folders { activeFolderID = nil }
            }
        )
    }

    private var primaryPane: AnyView {
        AnyView(Group {
            if isSearching {
                // Unified search results (all modes, includes subnotes)
                SearchResultsView(
                    results: searchResults,
                    query: searchText,
                    isDark: isDarkMode,
                    selectedNote: selectedNote,
                    onSelect: { note in select(note: note) }
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            } else {
                switch displayMode {
                case .grid:
                    libraryGridView
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                case .list:
                    libraryListView
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                case .folders:
                    libraryFoldersView
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: displayMode)
        .animation(.easeInOut(duration: 0.18), value: isSearching)
        .background(Color.clear)
        )
    }

    private var libraryGridView: some View {
        let ds = JottDS(isDark: isDarkMode)
        let notes = sortedVisibleNotes

        return GeometryReader { proxy in
            let spacing: CGFloat = 16
            let targetWidth: CGFloat = 260
            let usable = max(proxy.size.width, targetWidth)
            let cols = max(1, Int((usable + spacing) / (targetWidth + spacing)))
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: cols)

            ScrollView(showsIndicators: false) {
                if notes.isEmpty {
                    LibraryEmptyState(
                        title: searchText.isEmpty ? "No notes yet" : "No notes match this search",
                        message: searchText.isEmpty ? "Capture something and it will land here." : "Try a broader query or switch views."
                    )
                    .padding(.top, 56)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                        ForEach(notes, id: \.id) { note in
                            LibraryMinimalNoteCard(
                                note: note,
                                estimatedHeight: gridCardEstimatedHeight(for: note),
                                isSelected: selectedNoteIDs.contains(note.id),
                                isDarkMode: isDarkMode,
                                subnoteCount: viewModel.subnoteCount(of: note.id),
                                animationNamespace: gridCardNamespace,
                                isDragSelecting: $isDragSelectingNotes,
                                onActivate: { modifiers in
                                    select(note: note, modifiers: modifiers)
                                },
                                onDragSelect: { dragSelect(note: note) },
                                viewModel: viewModel
                            )
                            .contextMenu { noteContextMenu(for: note) }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var libraryListView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                if sortedVisibleNotes.isEmpty {
                    LibraryEmptyState(
                        title: searchText.isEmpty ? "Nothing here yet" : "No matches found",
                        message: searchText.isEmpty ? "Capture something and it will land here." : "Try a broader query or clear the search."
                    )
                } else {
                    ForEach(sortedVisibleNotes, id: \.id) { note in
                        TimelineItemView(
                            item: .note(note),
                            viewModel: viewModel,
                            isSelected: selectedNoteIDs.contains(note.id),
                            onSelect: { modifiers in
                                select(note: note, modifiers: modifiers)
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Folders View

    private var libraryFoldersView: some View {
        let ds = JottDS(isDark: isDarkMode)

        return Group {
            if let folderID = activeFolderID {
                // ── Notes inside a folder ──
                VStack(spacing: 0) {
                    // Back header
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(JottMotion.content) { activeFolderID = nil }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .semibold))
                                if let folder = noteStore.folders.first(where: { $0.id == folderID }) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(folder.displayColor)
                                    Text(folder.name)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                            }
                            .foregroundColor(ds.inkMute)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        let count = NoteStore.shared.notes(inFolder: folderID).count
                        Text("\(count) note\(count == 1 ? "" : "s")")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ds.inkFaintest)
                    }
                    .padding(.bottom, 14)

                    libraryFolderNotesGrid(folderID: folderID)
                }
            } else {
                // ── Folder cards grid ──
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // New folder button + section header
                        HStack {
                            Text("FOLDERS")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(ds.inkFaintest)
                                .tracking(1.2)
                            Spacer()
                            Button {
                                newFolderName = ""
                                showNewFolderSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("New Folder")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(ds.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(ds.accentSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        if noteStore.folders.isEmpty {
                            LibraryEmptyState(
                                title: "No folders yet",
                                message: "Create a folder to organise your notes."
                            )
                            .padding(.top, 24)
                        } else {
                            folderCardsGrid
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showNewFolderSheet) {
            NewFolderSheet(
                folderName: $newFolderName,
                isDark: isDarkMode,
                onCreate: { name, color in
                    _ = NoteStore.shared.createFolder(name: name, colorTag: color)
                    showNewFolderSheet = false
                },
                onCancel: { showNewFolderSheet = false }
            )
        }
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
    }

    private var folderCardsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 14)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(noteStore.folders) { folder in
                FolderCard(
                    folder: folder,
                    noteCount: NoteStore.shared.notes(inFolder: folder.id).count,
                    isDark: isDarkMode
                )
                .onTapGesture {
                    withAnimation(JottMotion.content) { activeFolderID = folder.id }
                }
                .contextMenu {
                    Button("Rename") {
                        renameFolderName = folder.name
                        renamingFolderID = folder.id
                        showRenameFolderSheet = true
                    }
                    Divider()
                    Button(role: .destructive) {
                        NoteStore.shared.deleteFolder(folder.id)
                    } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func libraryFolderNotesGrid(folderID: UUID) -> some View {
        let notes = NoteStore.shared.notes(inFolder: folderID)

        return GeometryReader { proxy in
            let spacing: CGFloat = 16
            let targetWidth: CGFloat = 260
            let usable = max(proxy.size.width, targetWidth)
            let cols = max(1, Int((usable + spacing) / (targetWidth + spacing)))
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: cols)

            if notes.isEmpty {
                FolderEmptyState()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                        ForEach(notes, id: \.id) { note in
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func noteContextMenu(for note: Note) -> some View {
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

        Divider()

        Button(role: .destructive) {
            selectedNoteIDs = [note.id]
            showDeleteConfirm = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var libraryScaffoldNotificationListener: some View {
        Color.clear.frame(width: 0, height: 0)
    }

    private func gridCardEstimatedHeight(for note: Note) -> CGFloat {
        let nonEmptyLines = note.text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let characterCount = nonEmptyLines.joined(separator: " ").count
        let hasImage = note.text.contains("![")
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
        withAnimation(JottMotion.content) {
            selectedItem = nil
            selectedNoteIDs.removeAll()
            selectionAnchorNoteID = nil
            isDetailExpanded = false
        }
    }

    private func deleteSelectedNotes() {
        let ids = selectedNoteIDs
        withAnimation(JottMotion.content) {
            showDeleteConfirm = false
            selectedItem = nil
            selectedNoteIDs.removeAll()
            selectionAnchorNoteID = nil
        }
        for id in ids { viewModel.deleteNote(id) }
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

    private func stripLibraryMarkup(from raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\[\[([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"!\[[^\]]*\]\(([^)]+)\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isImageOnlyLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^!\[[^\]]*\]\(([^)]+)\)$"#) else { return false }
        return regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
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

    private var subnotePreviews: [String] {
        NoteStore.shared.subnotes(of: note.id)
            .prefix(3)
            .compactMap { sub in
                sub.text.components(separatedBy: "\n")
                    .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            }
    }

    private var title: String {
        let lines = note.text.components(separatedBy: "\n")
        return lines.first { !isImageOnlyLine($0) && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "Untitled"
    }

    private var previewLines: [String] {
        let cleaned = note.text
            .components(separatedBy: "\n")
            .map { stripMarkup(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

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
        guard let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#) else { return nil }
        let source = note.text
        guard let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let pathRange = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[pathRange])
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
                    Image(systemName: "layers.2")
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
            // ── Stacked indicator (2 layers for subnotes) ──
            if subnoteCount > 0 {
                // Second layer (further back)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDarkMode ? Color(white: 0.08) : Color(white: 0.95))
                    .opacity(0.5)
                    .padding(.horizontal, 8)
                    .offset(x: 8, y: 8)

                // First layer (closer)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDarkMode ? Color(white: 0.08) : Color(white: 0.95))
                    .opacity(0.65)
                    .padding(.horizontal, 8)
                    .offset(x: 4, y: 4)
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

                Text(stripMarkup(from: title))
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

    private func stripMarkup(from raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\[\[([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"!\[[^\]]*\]\(([^)]+)\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func isImageOnlyLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^!\[[^\]]*\]\(([^)]+)\)$"#) else { return false }
        return regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
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

        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // ── Header ──
                HStack(spacing: 8) {
                    // Mono meta: date · relative time
                    Text("\(formattedDate)  ·  \(relativeTimeLabel)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(ds.inkFaint)
                        .tracking(0.3)

                    Spacer()

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

                        // Inline subnote input (shown after tapping squish)
                        if showingSubnoteInput {
                            subnoteInputRow
                                .padding(.top, 12)
                        }

                        Spacer().frame(height: 72) // room for FAB
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                }
            }

            // ── Add subnote button (bottom-right, quiet) ──
            Button {
                withAnimation(JottMotion.content) { showingSubnoteInput = true }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Add subnote")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(squishColor)
                )
            }
            .buttonStyle(SquishButtonStyle())
            .padding(.trailing, 18)
            .padding(.bottom, 18)
            .opacity(showingSubnoteInput ? 0 : 1)
            .scaleEffect(showingSubnoteInput ? 0.88 : 1)
            .animation(JottMotion.micro, value: showingSubnoteInput)
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

            Button {
                withAnimation(JottMotion.content) { showingSubnoteInput = true }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    Text("Add subnote").font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(squishColor))
            }
            .buttonStyle(SquishButtonStyle())
            .padding(.trailing, 16)
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

                Text("Delete \(count) \(count == 1 ? "note" : "notes")?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.92) : .black.opacity(0.86))
                    .padding(.bottom, 6)

                Text("This can't be undone.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.55))
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
                        Text("Delete")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            FolderIconView(color: folder.displayColor, size: 72)
                .scaleEffect(hovered ? 1.04 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.62), value: hovered)

            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ds.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("\(noteCount) note\(noteCount == 1 ? "" : "s")")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(ds.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDark ? Color.white.opacity(hovered ? 0.07 : 0.04) : Color.black.opacity(hovered ? 0.04 : 0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            hovered ? folder.displayColor.opacity(0.35) : ds.hairline,
                            lineWidth: 1
                        )
                )
        )
        .onHover { h in withAnimation(.easeInOut(duration: 0.14)) { hovered = h } }
    }
}

// MARK: - New Folder Sheet

private struct NewFolderSheet: View {
    @Binding var folderName: String
    let isDark: Bool
    let onCreate: (String, FolderColorTag) -> Void
    let onCancel: () -> Void

    @State private var selectedColor: FolderColorTag = .lavender
    @FocusState private var nameFieldFocused: Bool

    private var ds: JottDS { JottDS(isDark: isDark) }

    // 2 rows × 5 columns
    private let tagRows: [[FolderColorTag]] = {
        let all = FolderColorTag.allCases
        return stride(from: 0, to: all.count, by: 5).map {
            Array(all[$0..<min($0 + 5, all.count)])
        }
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ── Live preview ──
            HStack(spacing: 14) {
                FolderIconView(color: selectedColor.color, size: 56)
                    .animation(.spring(response: 0.26, dampingFraction: 0.70), value: selectedColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("New Folder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ds.ink)
                    Text(folderName.isEmpty ? "Untitled" : folderName)
                        .font(.system(size: 12))
                        .foregroundColor(ds.inkFaint)
                        .lineLimit(1)
                }
            }

            // ── Name field ──
            TextField("Folder name", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFieldFocused)
                .onSubmit { commitIfValid() }

            // ── Colour picker ──
            VStack(alignment: .leading, spacing: 9) {
                Text("COLOUR")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(ds.inkFaintest)
                    .tracking(1.2)

                ForEach(tagRows.indices, id: \.self) { rowIdx in
                    HStack(spacing: 9) {
                        ForEach(tagRows[rowIdx], id: \.self) { tag in
                            ZStack(alignment: .bottom) {
                                FolderIconView(color: tag.color, size: 44)
                                // Selection ring
                                if selectedColor == tag {
                                    Capsule()
                                        .fill(tag.color)
                                        .frame(width: 18, height: 4)
                                        .offset(y: 6)
                                }
                            }
                            .padding(.bottom, 6)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedColor = tag }
                        }
                    }
                }
            }

            // ── Actions ──
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
                Button("Create") { commitIfValid() }
                    .keyboardShortcut(.return)
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 350)
        .background(ds.canvas)
        .colorScheme(isDark ? .dark : .light)
        .onAppear { nameFieldFocused = true }
    }

    private func commitIfValid() {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed, selectedColor)
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
            .contentShape(Rectangle())

            // Hairline divider
            Rectangle()
                .fill(ds.hairline)
                .frame(height: 1)
                .padding(.horizontal, 12)
        }
        .contextMenu {
            if case .note(let note) = item {
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
        note.text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Untitled"
    }

    private func notePreview(for note: Note) -> String? {
        let lines = note.text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return nil }
        return lines[1]
    }
}

// MARK: - Search Results View

private struct SearchResultsView: View {
    let results: [SearchResult]
    let query: String
    let isDark: Bool
    let selectedNote: Note?
    let onSelect: (Note) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            if results.isEmpty {
                LibraryEmptyState(
                    title: "No results",
                    message: "Nothing matched \"\(query)\". Try a different phrasing or add more context."
                )
                .padding(.top, 56)
            } else {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(results) { result in
                        SearchResultRow(
                            result: result,
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

private struct SearchResultRow: View {
    let result: SearchResult
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
        note.text.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? "Untitled"
    }

    private var bodyPreview: String? {
        let lines = note.text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return nil }
        return lines.dropFirst().prefix(2).joined(separator: "  ·  ")
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
        VStack(alignment: .leading, spacing: 2) {
            if isSubnote, let parent = result.parentNote {
                Text(parentTitle(parent))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.40))
                    .lineLimit(1)
            }
            Text(title)
                .font(.system(size: 13, weight: isSubnote ? .regular : .medium))
                .foregroundColor(isDark ? .white.opacity(0.88) : .black.opacity(0.84))
                .lineLimit(1)
            if !isSubnote, let preview = bodyPreview {
                Text(preview)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary.opacity(0.50))
                    .lineLimit(1)
            }
        }
    }

    private func parentTitle(_ parent: Note) -> String {
        parent.text.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Untitled"
    }
}

private struct LibraryTopBar: View {
    @Binding var searchText: String
    @Binding var displayMode: LibraryDisplayMode
    @Binding var activeFilter: LibraryFilter
    let visibleCount: Int
    var selectedCount: Int = 0
    let isDarkMode: Bool
    let selectedNote: Note?
    var availableTags: [String] = []
    var onDismissDetail: (() -> Void)? = nil
    var onDeleteSelected: (() -> Void)? = nil

    @State private var showFilterPopover = false
    private var isSearching: Bool { !searchText.isEmpty }
    private var hasSelection: Bool { selectedCount > 1 }

    var body: some View {
        let ds = JottDS(isDark: isDarkMode)

        HStack(spacing: 10) {
            // Title + inline mono count
            HStack(spacing: 6) {
                Text("Notes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ds.ink)
                Text("\(visibleCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ds.inkFaintest)
                    .tracking(0.3)
            }

            // View mode toggle — hidden when multi-selecting or searching
            if !isSearching && !hasSelection {
                HStack(spacing: 2) {
                    ForEach(LibraryDisplayMode.allCases, id: \.self) { mode in
                        modeButton(mode, ds: ds)
                    }
                }
                .padding(3)
                .background(ds.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(ds.hairline, lineWidth: 1)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
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
                            Text("Delete")
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
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .frame(height: 56)
        .background(isDarkMode ? Color.white.opacity(0.006) : Color.white.opacity(0.80))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSearching)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: hasSelection)
    }

    private func modeButton(_ mode: LibraryDisplayMode, ds: JottDS) -> some View {
        let isActive = displayMode == mode
        return Button {
            withAnimation(JottMotion.content) { displayMode = mode }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 10.5, weight: .medium))
                    .symbolEffect(.bounce, options: .nonRepeating, value: isActive)
                Text(mode.rawValue)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundColor(isActive ? ds.ink : ds.inkFaint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? ds.surface : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isActive ? ds.hairlineMid : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
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
        VStack(spacing: 0) {
            // Icon cluster
            ZStack {
                // Background glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.58, green: 0.50, blue: 0.92).opacity(0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 48
                        )
                    )
                    .frame(width: 96, height: 96)

                // Stacked cards illustration
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.58, green: 0.50, blue: 0.92).opacity(0.10))
                    .frame(width: 40, height: 32)
                    .rotationEffect(.degrees(-10))
                    .offset(x: -8, y: 4)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.58, green: 0.50, blue: 0.92).opacity(0.16))
                    .frame(width: 40, height: 32)
                    .rotationEffect(.degrees(5))
                    .offset(x: 6, y: 2)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.58, green: 0.50, blue: 0.92).opacity(0.28))
                    .frame(width: 40, height: 32)
                    .overlay(
                        Image(systemName: "pencil.line")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 0.58, green: 0.50, blue: 0.92).opacity(0.70))
                    )
            }
            .scaleEffect(appeared ? 1.0 : 0.82)
            .opacity(appeared ? 1.0 : 0)

            Spacer().frame(height: 20)

            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.72))
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)

            Spacer().frame(height: 6)

            Text(message)
                .font(.system(size: 12.5))
                .foregroundColor(.secondary.opacity(0.68))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.05)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
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
    @State private var editingText = ""
    @FocusState private var isEditorFocused: Bool

    private var isDarkMode: Bool {
        viewModel.isDarkMode
    }

    private var title: String {
        let lines = note.text.components(separatedBy: "\n")
        return lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? "Untitled"
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
            editingText = note.text
            isEditing = true
            DispatchQueue.main.async { isEditorFocused = true }
        }
        .onChange(of: note.id) { _, _ in
            editingText = note.text
            isEditing = true
            DispatchQueue.main.async { isEditorFocused = true }
        }
        .onChange(of: editRequestToken) { _, _ in
            editingText = note.text
            isEditing = true
            DispatchQueue.main.async { isEditorFocused = true }
        }
        .onChange(of: note.text) { _, newValue in
            if !isEditing { editingText = newValue }
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
                    if let updated = viewModel.updateNote(note, text: editingText) {
                        editingText = updated.text
                        isEditing = false
                    }
                } else {
                    editingText = note.text
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
                LibraryAIInlineEditor(
                    text: $editingText,
                    suggestion: nil,
                    isDark: isDarkMode,
                    onTextChange: nil,
                    onSuggestionAccepted: {},
                    onSuggestionDismissed: {}
                )
                .frame(minHeight: 220)
            } else {
                NoteRichContentView(
                    text: note.text,
                    isDarkMode: isDarkMode,
                    onTap: {
                        editingText = note.text
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

private struct LibraryAIInlineEditor: NSViewRepresentable {
    @Binding var text: String
    var suggestion: String?
    var isDark: Bool
    var onTextChange: ((String) -> Void)?
    var onSuggestionAccepted: () -> Void
    var onSuggestionDismissed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 14)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero

        scrollView.documentView = textView
        context.coordinator.textView = textView
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self

        let textColor: NSColor = isDark
            ? .white.withAlphaComponent(0.90)
            : .black.withAlphaComponent(0.85)
        let ghostColor: NSColor = isDark
            ? NSColor(white: 0.72, alpha: 0.42)
            : NSColor(white: 0.58, alpha: 0.72)
        let font = NSFont.systemFont(ofSize: 14)
        let targetString = text + (suggestion ?? "")

        if textView.textStorage?.string != targetString {
            let savedSelection = textView.selectedRange()
            let attributed = NSMutableAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: textColor]
            )
            if let suggestion, !suggestion.isEmpty {
                attributed.append(
                    NSAttributedString(
                        string: suggestion,
                        attributes: [.font: font, .foregroundColor: ghostColor]
                    )
                )
                coordinator.ghostStart = text.utf16.count
            } else {
                coordinator.ghostStart = nil
            }

            textView.textStorage?.setAttributedString(attributed)
            textView.setSelectedRange(NSRange(location: min(savedSelection.location, text.utf16.count), length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LibraryAIInlineEditor
        weak var textView: NSTextView?
        var ghostStart: Int? = nil

        init(_ parent: LibraryAIInlineEditor) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard let ghostStart else { return true }
            let totalLength = textView.textStorage?.length ?? 0
            if totalLength > ghostStart {
                textView.textStorage?.deleteCharacters(in: NSRange(location: ghostStart, length: totalLength - ghostStart))
            }
            self.ghostStart = nil
            DispatchQueue.main.async { self.parent.onSuggestionDismissed() }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let newText = textView.string
            parent.text = newText
            parent.onTextChange?(newText)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertTab(_:)), let ghostStart {
                guard let storage = textView.textStorage else { return false }
                let totalLength = storage.length
                let ghostRange = NSRange(location: ghostStart, length: totalLength - ghostStart)
                let realAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: parent.isDark
                        ? NSColor.white.withAlphaComponent(0.90)
                        : NSColor.black.withAlphaComponent(0.85)
                ]
                storage.setAttributes(realAttributes, range: ghostRange)
                self.ghostStart = nil
                parent.text = storage.string
                parent.onSuggestionAccepted()
                textView.setSelectedRange(NSRange(location: storage.length, length: 0))
                return true
            }

            if selector == #selector(NSResponder.cancelOperation(_:)), let ghostStart {
                let totalLength = textView.textStorage?.length ?? 0
                if totalLength > ghostStart {
                    textView.textStorage?.deleteCharacters(in: NSRange(location: ghostStart, length: totalLength - ghostStart))
                }
                self.ghostStart = nil
                parent.onSuggestionDismissed()
                return true
            }

            return false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView,
                  let ghostStart else { return }
            let selection = textView.selectedRange()
            if selection.location > ghostStart {
                textView.setSelectedRange(NSRange(location: ghostStart, length: 0))
            }
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
