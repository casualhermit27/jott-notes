import SwiftUI

// MARK: - Filter

enum IOSLibraryFilter: Equatable {
    case none, pinned, today, thisWeek, thisMonth, recentlyDeleted
    case tagged(String)

    var label: String {
        switch self {
        case .none:            return "All"
        case .pinned:          return "Pinned"
        case .today:           return "Today"
        case .thisWeek:        return "This Week"
        case .thisMonth:       return "This Month"
        case .recentlyDeleted: return "Recently Deleted"
        case .tagged(let t):   return "#\(t)"
        }
    }

    var isActive: Bool { self != .none }
}

// MARK: - Main view

struct IOSLibraryView: View {
    @Binding var selectedNote: Note?
    @Binding var folderStack: [UUID]
    @Binding var activeFilter: IOSLibraryFilter
    @Binding var showSettings: Bool
    @ObservedObject private var noteStore = NoteStore.shared
    @Environment(\.colorScheme) private var scheme

    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var isEditMode = false
    @State private var selectedNoteIDs: Set<UUID> = []

    @State private var searchResults: [SearchResult] = []
    @State private var showNewNote = false
    @State private var showNewFolder = false
    @State private var isSyncing = false
    @State private var initialSyncDone = false
    @State private var showSyncTick = false
    @State private var folderToRename: NoteFolder? = nil
    @State private var folderToDelete: NoteFolder? = nil
    @State private var noteToShare: Note? = nil

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }
    private var activeFolderID: UUID? { folderStack.last }
    private var isSearching: Bool { !searchText.isEmpty }
    private var isRecentlyDeleted: Bool { activeFilter == .recentlyDeleted }

    private var availableTags: [String] {
        Array(Set(noteStore.allNotes().flatMap { $0.tags })).sorted()
    }

    private var filteredNotes: [Note] {
        if isRecentlyDeleted { return noteStore.deletedNotes().filter { $0.parentId == nil } }
        if isSearching { return searchResults.compactMap { $0.isSubnote ? nil : $0.note } }
        var base = noteStore.allNotes().filter { $0.parentId == nil }
        if let fid = activeFolderID { base = base.filter { $0.folderId == fid } }
        switch activeFilter {
        case .none:            return base
        case .pinned:          return base.filter { $0.isPinned }
        case .tagged(let t):   return base.filter { $0.tags.contains(t) }
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            return base.filter { $0.modifiedAt >= start }
        case .thisWeek:
            let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return base.filter { $0.modifiedAt >= start }
        case .thisMonth:
            let start = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            return base.filter { $0.modifiedAt >= start }
        case .recentlyDeleted: return base
        }
    }

    private var sortedNotes: [Note] {
        isSearching ? filteredNotes : filteredNotes.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // List drives NavigationSplitView selection — required for iPhone push navigation
            List(selection: $selectedNote) {

                // Folder chips
                if !isSearching && !isRecentlyDeleted {
                    folderChipStrip
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .selectionDisabled()
                }

                // Folder breadcrumb (subfolder navigation)
                if !folderStack.isEmpty && !isSearching && !isRecentlyDeleted {
                    folderBreadcrumb
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                }

                if isSyncing && !initialSyncDone && sortedNotes.isEmpty {
                    // Skeleton loader during initial sync
                    ForEach(0..<5, id: \.self) { i in
                        SkeletonCard(ds: ds, index: i)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                } else if sortedNotes.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(sortedNotes) { note in
                        NoteCard(
                            note: note,
                            subnoteCount: noteStore.subnoteCount(of: note.id),
                            isSelected: selectedNote?.id == note.id,
                            isEditMode: isEditMode,
                            isMultiSelected: selectedNoteIDs.contains(note.id),
                            searchQuery: searchText,
                            ds: ds,
                            onEditTap: isEditMode ? {
                                Haptics.light()
                                if selectedNoteIDs.contains(note.id) {
                                    selectedNoteIDs.remove(note.id)
                                } else {
                                    selectedNoteIDs.insert(note.id)
                                }
                            } : nil
                        )
                        .tag(note)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            swipeButtons(for: note)
                        }
                        .contextMenu {
                            Button {
                                noteStore.togglePin(note.id)
                            } label: {
                                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                            }

                            Button {
                                if let url = noteStore.exportNoteAsMarkdown(note) {
                                    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let root = windowScene.windows.first?.rootViewController {
                                        root.present(activity, animated: true)
                                    }
                                }
                            } label: {
                                Label("Export as Markdown", systemImage: "square.and.arrow.up")
                            }

                            Menu {
                                Button("Remove from Folder") {
                                    noteStore.moveNote(note.id, toFolder: nil)
                                }
                                Divider()
                                ForEach(noteStore.folders) { folder in
                                    Button(folder.name) {
                                        noteStore.moveNote(note.id, toFolder: folder.id)
                                    }
                                }
                            } label: {
                                Label("Move to Folder", systemImage: "folder")
                            }

                            Button(role: .destructive) {
                                noteStore.deleteNote(note.id)
                                if selectedNote?.id == note.id { selectedNote = nil }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    // Bottom padding row so FAB doesn't cover last card
                    Color.clear.frame(height: 80)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ds.canvas)
            .refreshable { await triggerSync() }
            .searchable(text: $searchText, isPresented: $isSearchPresented,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search notes")
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .task(id: searchText) {
                guard !searchText.isEmpty else { searchResults = []; return }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let q = searchText
                let results = SearchEngine.shared.search(query: q, store: noteStore)
                guard !Task.isCancelled else { return }
                searchResults = results
            }
            .onAppear {
                if !initialSyncDone {
                    isSyncing = true
                    noteStore.refreshFromDisk()
                    Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        withAnimation(.easeOut(duration: 0.3)) {
                            isSyncing = false
                            initialSyncDone = true
                            showSyncTick = true
                        }
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.easeOut(duration: 0.3)) {
                            showSyncTick = false
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .jottFocusSearch)) { _ in
                withAnimation {
                    isSearchPresented = true
                }
            }
            .fullScreenCover(isPresented: $showNewNote) {
                IOSNewNoteComposerView(
                    title: "New Note",
                    folderId: activeFolderID,
                    parentId: nil
                ) { note in
                    selectedNote = note
                }
            }
                .sheet(isPresented: $showNewFolder) {
                    IOSFolderComposerView(folderId: activeFolderID)
                }
                .sheet(item: $noteToShare) { note in
                    if let url = noteStore.exportNoteAsMarkdown(note) {
                        ShareSheetView(items: [url])
                            .presentationDetents([.medium, .large])
                    }
                }
                .sheet(item: $folderToRename) { folder in
                    IOSFolderRenameView(folder: folder, onSave: { newName in
                        noteStore.renameFolder(folder.id, to: newName)
                        folderToRename = nil
                    }, onCancel: {
                        folderToRename = nil
                    })
                }
            .confirmationDialog(
                "Delete \"\(folderToDelete?.name ?? "")\"?",
                isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Folder", role: .destructive) {
                    if let f = folderToDelete {
                        if folderStack.last == f.id { folderStack.removeLast() }
                        noteStore.deleteFolder(f.id)
                    }
                    folderToDelete = nil
                }
                Button("Cancel", role: .cancel) { folderToDelete = nil }
            } message: {
                Text("Notes inside will be moved to All Notes.")
            }

            // FAB — only shown when not in trash
            if !isRecentlyDeleted {
                fabButton
            }
        }
    }

    // MARK: - Sync

    private func triggerSync() async {
        isSyncing = true
        noteStore.refreshFromDisk()
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation(.easeOut(duration: 0.3)) {
            isSyncing = false
            initialSyncDone = true
            showSyncTick = true
        }
        try? await Task.sleep(for: .seconds(2))
        withAnimation(.easeOut(duration: 0.3)) {
            showSyncTick = false
        }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            Haptics.medium()
            showNewNote = true
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(ds.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 28)
    }

    // MARK: - Folder breadcrumb

    @ViewBuilder
    private var folderBreadcrumb: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Prominent back button
            Button {
                withAnimation(JottMotion.content) {
                    _ = folderStack.removeLast()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text(parentFolderLabel)
                        .font(.jottBody(16, weight: .semibold))
                }
                .foregroundStyle(ds.accent)
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            // Path trail — only shown when 2+ levels deep
            if folderStack.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        Button {
                            withAnimation(JottMotion.content) { folderStack = [] }
                        } label: {
                            Image(systemName: "house")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ds.accent)
                        }
                        .buttonStyle(.plain)

                        ForEach(Array(folderStack.enumerated()), id: \.element) { idx, fid in
                            if let folder = noteStore.folders.first(where: { $0.id == fid }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(ds.inkFaintest)
                                Button {
                                    withAnimation(JottMotion.content) {
                                        folderStack = Array(folderStack.prefix(idx + 1))
                                    }
                                } label: {
                                    Text(folder.name)
                                        .font(.jottCaption(11, weight: .medium))
                                        .foregroundStyle(idx == folderStack.count - 1 ? ds.inkMute : ds.accent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var parentFolderLabel: String {
        guard folderStack.count > 1 else { return "All Notes" }
        let parentId = folderStack[folderStack.count - 2]
        return noteStore.folders.first(where: { $0.id == parentId })?.name ?? "All Notes"
    }

    // folder context menu (used by chip long-press in the future)
    private func folderContextMenuItems(_ folder: NoteFolder) -> some View {
        Group {
            Button {
                folderToRename = folder
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                folderToDelete = folder
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Folder chips

    private var folderChipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                allChip
                folderChips
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }

    private var allChip: some View {
        let isActive = folderStack.isEmpty && activeFilter == .none
        return Button {
            withAnimation(JottMotion.content) { folderStack = []; activeFilter = .none }
        } label: {
            folderChipLabel("All", isActive: isActive)
        }
        .buttonStyle(.plain)
    }

    private var folderChips: some View {
        ForEach(noteStore.folders.filter { $0.parentId == nil }) { folder in
            let isActive = folderStack.last == folder.id
            Menu {
                Button { folderToRename = folder } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) { folderToDelete = folder } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                folderChipLabel(folder.name, icon: "folder.fill",
                                color: folder.displayColor, isActive: isActive)
            } primaryAction: {
                withAnimation(JottMotion.content) {
                    if isActive {
                        folderStack = []
                    } else {
                        folderStack = [folder.id]
                        activeFilter = .none
                    }
                }
            }
        }
    }

    private func folderChipLabel(
        _ name: String,
        icon: String? = nil,
        color: Color = .clear,
        isActive: Bool
    ) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isActive ? .white : color != .clear ? color : ds.inkMute)
            }
            Text(name)
                .font(.jottCaption(13, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .white : ds.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            isActive ? (color != .clear ? color : ds.accent) : ds.surface,
            in: Capsule()
        )
        .overlay(Capsule().strokeBorder(isActive ? Color.clear : ds.hairline, lineWidth: 1))
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            if isSyncing {
                ProgressView()
                    .tint(ds.accent)
                Text("Syncing with iCloud...")
                    .font(.jottBody(14))
                    .foregroundStyle(ds.inkFaint)
            } else {
                Image(systemName: isRecentlyDeleted ? "trash" : (isSearching ? "magnifyingglass" : "note.text"))
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(ds.inkFaintest)
                Text(emptyStateLabel)
                    .font(.jottBody(15))
                    .foregroundStyle(ds.inkFaint)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 40)
    }

    private var emptyStateLabel: String {
        if isSearching { return "No results for \"\(searchText)\"" }
        if isRecentlyDeleted { return "Recently Deleted is empty" }
        return "No notes yet\nPull down to sync from iCloud\nor tap + to create one"
    }

    private var navigationTitle: String {
        if isRecentlyDeleted { return "Recently Deleted" }
        if let fid = activeFolderID, let folder = noteStore.folders.first(where: { $0.id == fid }) {
            return folder.name
        }
        return activeFilter.label == "All" ? "Notes" : activeFilter.label
    }

    // MARK: - Swipe actions

    @ViewBuilder
    private func swipeButtons(for note: Note) -> some View {
        if isRecentlyDeleted {
            Button(role: .destructive) {
                noteStore.permanentlyDeleteNote(note.id)
                if selectedNote?.id == note.id { selectedNote = nil }
            } label: {
                swipeLabel("Delete", icon: "trash.fill")
            }
            Button {
                noteStore.restoreNote(note.id)
            } label: {
                swipeLabel("Restore", icon: "arrow.uturn.backward")
            }
            .tint(Color(red: 0.18, green: 0.72, blue: 0.42))
        } else {
            Button(role: .destructive) {
                noteStore.deleteNote(note.id)
                if selectedNote?.id == note.id { selectedNote = nil }
            } label: {
                swipeLabel("Delete", icon: "trash.fill")
            }
            Button {
                noteStore.togglePin(note.id)
            } label: {
                swipeLabel(note.isPinned ? "Unpin" : "Pin",
                           icon: note.isPinned ? "pin.slash.fill" : "pin.fill")
            }
            .tint(Color(red: 0.98, green: 0.62, blue: 0.12))
            Button {
                noteToShare = note
            } label: {
                swipeLabel("Share", icon: "square.and.arrow.up.fill")
            }
            .tint(Color(red: 0.34, green: 0.54, blue: 0.98))
        }
    }

    private func swipeLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
            Text(title)
                .font(.jottCaption(11, weight: .semibold))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if !isSearching && !isRecentlyDeleted {
                Button {
                    showNewFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ds.inkMute)
                }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if isEditMode {
                if !selectedNoteIDs.isEmpty {
                    HStack(spacing: 16) {
                        Button {
                            let urls = selectedNoteIDs.compactMap { id in
                                noteStore.allNotes().first(where: { $0.id == id })
                            }.compactMap { noteStore.exportNoteAsMarkdown($0) }
                            if !urls.isEmpty {
                                let activity = UIActivityViewController(activityItems: urls, applicationActivities: nil)
                                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                   let root = windowScene.windows.first?.rootViewController {
                                    root.present(activity, animated: true)
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(ds.accent)
                        }
                        Button(role: .destructive) {
                            for id in selectedNoteIDs { noteStore.deleteNote(id) }
                            selectedNoteIDs.removeAll()
                            isEditMode = false
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    Button {
                        selectedNoteIDs = Set(sortedNotes.map { $0.id })
                    } label: {
                        Text("Select All")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(ds.accent)
                    }
                }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                filterMenuItems
            } label: {
                Image(systemName: activeFilter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(activeFilter.isActive ? ds.accent : ds.inkMute)
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if isSyncing {
                ProgressView()
                    .tint(ds.accent)
                    .scaleEffect(0.8)
            } else if showSyncTick {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.purple)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            HStack(spacing: 12) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ds.inkMute)
                }
                Button {
                    isEditMode.toggle()
                    if !isEditMode { selectedNoteIDs.removeAll() }
                } label: {
                    Text(isEditMode ? "Done" : "Edit")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ds.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var filterMenuItems: some View {
        Button { withAnimation { activeFilter = .none } } label: {
            Label("All Notes", systemImage: "note.text")
        }
        Button { withAnimation { activeFilter = .pinned } } label: {
            Label("Pinned", systemImage: "pin")
        }
        Divider()
        Button { withAnimation { activeFilter = .today } } label: {
            Label("Today", systemImage: "calendar")
        }
        Button { withAnimation { activeFilter = .thisWeek } } label: {
            Label("This Week", systemImage: "calendar.badge.clock")
        }
        Button { withAnimation { activeFilter = .thisMonth } } label: {
            Label("This Month", systemImage: "calendar.badge.clock")
        }
        if !availableTags.isEmpty {
            Divider()
            ForEach(availableTags, id: \.self) { tag in
                Button { withAnimation { activeFilter = .tagged(tag) } } label: {
                    Label("#\(tag)", systemImage: "tag")
                }
            }
        }
        Divider()
        Button { withAnimation { activeFilter = .recentlyDeleted } } label: {
            Label("Recently Deleted", systemImage: "trash")
        }
    }
}

// MARK: - Note card

// MARK: - Skeleton card

private struct SkeletonCard: View {
    let ds: JottDS
    let index: Int
    @State private var pulse = false

    // Vary widths per card so it looks natural
    private var titleWidth: CGFloat { [0.75, 0.55, 0.85, 0.60, 0.70][index % 5] }
    private var bodyWidth: CGFloat  { [0.90, 0.65, 0.80, 0.95, 0.72][index % 5] }
    private var bodyWidth2: CGFloat { [0.50, 0.80, 0.45, 0.70, 0.58][index % 5] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Meta row
            HStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(ds.surfaceAlt)
                    .frame(width: 48, height: 9)
                Spacer()
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(ds.surfaceAlt)
                    .frame(width: 32, height: 9)
            }

            Spacer().frame(height: 12)

            // Title
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(ds.surfaceAlt)
                .frame(maxWidth: .infinity)
                .frame(height: 14)
                .padding(.trailing, (1 - titleWidth) * 120)

            Spacer().frame(height: 8)

            // Body line 1
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ds.surfaceAlt.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 11)
                .padding(.trailing, (1 - bodyWidth) * 80)

            Spacer().frame(height: 6)

            // Body line 2
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ds.surfaceAlt.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 11)
                .padding(.trailing, (1 - bodyWidth2) * 100)

            Spacer().frame(height: 14)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ds.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(ds.hairline, lineWidth: 1))
        .opacity(pulse ? 0.5 : 1.0)
        .animation(
            .easeInOut(duration: 0.9)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.12),
            value: pulse
        )
        .onAppear { pulse = true }
    }
}

// MARK: - Note card

private struct NoteCard: View {
    let note: Note
    let subnoteCount: Int
    let isSelected: Bool
    let isEditMode: Bool
    let isMultiSelected: Bool
    var searchQuery: String = ""
    let ds: JottDS
    var onEditTap: (() -> Void)? = nil

    private var preview: (title: String, body: String) { jottNotePreview(note) }
    private var isSearching: Bool { !searchQuery.isEmpty }

    var body: some View {
        let card = HStack(spacing: 12) {
            if isEditMode {
                Image(systemName: isMultiSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isMultiSelected ? ds.accent : ds.inkFaintest)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            ZStack(alignment: .top) {
                // Depth layers for notes that have subnotes
                if subnoteCount > 0 {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ds.surfaceAlt.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(ds.hairline, lineWidth: 1))
                        .padding(.horizontal, 10)
                        .offset(y: 7)

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ds.surfaceAlt.opacity(0.8))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(ds.hairline, lineWidth: 1))
                        .padding(.horizontal, 5)
                        .offset(y: 3.5)
                }

                // Main card
                VStack(alignment: .leading, spacing: 0) {
                    // Metadata row
                    HStack(spacing: 0) {
                        Text(jottMetaDate(note.modifiedAt))
                            .font(.jottMono(10, weight: .medium))
                            .foregroundStyle(ds.inkFaintest)
                            .tracking(0.4)
                        Spacer()
                        if note.isPinned {
                            Text("PINNED")
                                .font(.jottMono(9, weight: .medium))
                                .foregroundStyle(ds.accent.opacity(0.45))
                                .tracking(0.6)
                                .padding(.trailing, 6)
                        }
                        Text(jottRelativeDate(note.modifiedAt))
                            .font(.jottMono(10))
                            .foregroundStyle(ds.inkFaintest)
                            .tracking(0.4)
                    }

                    Spacer().frame(height: 10)

                    Text(highlightedAttributedString(
                        preview.title,
                        matching: searchQuery,
                        size: 15, weight: .medium,
                        baseColor: ds.ink,
                        highlightColor: ds.accent
                    ))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(1)

                    if !preview.body.isEmpty {
                        Spacer().frame(height: 7)
                        Text(highlightedAttributedString(
                            preview.body,
                            matching: searchQuery,
                            size: 13,
                            baseColor: ds.inkMute,
                            highlightColor: ds.accent
                        ))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(2)
                    }

                    let hasTags = !note.tags.isEmpty
                    if hasTags || subnoteCount > 0 {
                        Spacer().frame(height: 10)
                        HStack(spacing: 6) {
                            if hasTags {
                                ForEach(note.tags.prefix(3), id: \.self) { tag in
                                    JottTagChip(tag: tag, ds: ds)
                                }
                            }
                            Spacer(minLength: 0)
                            if subnoteCount > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "square.stack")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text("\(subnoteCount)")
                                        .font(.jottMono(9, weight: .semibold))
                                }
                                .foregroundStyle(ds.accent.opacity(0.75))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(ds.accentSoft, in: Capsule())
                                .overlay(Capsule().strokeBorder(ds.accent.opacity(0.18), lineWidth: 0.8))
                            }
                        }
                    }

                    Spacer().frame(height: 14)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ds.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? ds.accentRing : ds.hairline,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
            }
        }
        // Extra bottom clearance so the depth layers don't visually crowd the next card
        .padding(.bottom, subnoteCount > 0 ? 10 : 0)
        .contentShape(Rectangle())

        if let onEditTap = onEditTap {
            Button(action: onEditTap) {
                card
            }
            .buttonStyle(.plain)
        } else {
            card
        }
    }
}

// MARK: - Folder rename sheet

private struct IOSFolderRenameView: View {
    let folder: NoteFolder
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @Environment(\.colorScheme) private var scheme
    private var ds: JottDS { JottDS(isDark: scheme == .dark) }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(folder: NoteFolder, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.folder = folder
        self.onSave = onSave
        self.onCancel = onCancel
        self._name = State(initialValue: folder.name)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ds.canvas.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(folder.displayColor.opacity(0.16))
                                .frame(width: 42, height: 42)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(folder.displayColor.opacity(0.28), lineWidth: 1))
                            Image(systemName: "folder.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(folder.displayColor)
                        }
                        Text("Rename Folder")
                            .font(.jottBody(16, weight: .semibold))
                            .foregroundStyle(ds.ink)
                        Spacer()
                    }

                    TextField("Folder name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        .textFieldStyle(.plain)
                        .font(.jottBody(15))
                        .foregroundStyle(ds.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(ds.surfaceAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(ds.hairline, lineWidth: 1))

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(ds.inkMute)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(trimmed) }
                        .fontWeight(.semibold)
                        .foregroundStyle(trimmed.isEmpty || trimmed == folder.name ? ds.inkFaintest : ds.accent)
                        .disabled(trimmed.isEmpty || trimmed == folder.name)
                }
            }
        }
    }
}

// MARK: - Share sheet

private struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
