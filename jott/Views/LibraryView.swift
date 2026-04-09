import SwiftUI
import AppKit

private enum LibraryDisplayMode: String, CaseIterable {
    case grid    = "Grid"
    case list    = "List"
    case outline = "Tree"

    var icon: String {
        switch self {
        case .grid:    return "square.grid.2x2"
        case .list:    return "list.bullet"
        case .outline: return "list.triangle"
        }
    }
}

private enum LibrarySelection: Equatable {
    case note(UUID)
    case reminder(UUID)
}

struct LibraryView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var searchText: String = ""
    @State private var selectedItem: LibrarySelection?
    @State private var selectedNoteIDs: Set<UUID> = []
    @State private var displayMode: LibraryDisplayMode = .grid
    @State private var selectionAnchorNoteID: UUID?
    @State private var isDragSelectingNotes = false
    @State private var isDetailExpanded: Bool = false
    @State private var searchMode: SearchMode = .normal
    private var isDarkMode: Bool {
        viewModel.isDarkMode
    }

    // When searching: results from SearchEngine (includes subnotes).
    // When idle: all root notes sorted by date.
    private var searchResults: [SearchResult] {
        guard !searchText.isEmpty else { return [] }
        return SearchEngine.shared.search(query: searchText, store: NoteStore.shared, mode: searchMode)
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private var filteredNotes: [Note] {
        if isSearching {
            return searchResults.compactMap { r in
                r.isSubnote ? nil : r.note
            }
        }
        return viewModel.getAllNotes().filter { $0.parentId == nil }
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
                    searchMode: $searchMode,
                    visibleCount: filteredItemCount,
                    isDarkMode: isDarkMode,
                    selectedNote: selectedNote,
                    onDismissDetail: { clearSelection() }
                )

                Divider()
                    .opacity(isDarkMode ? 0.16 : 0.10)

                ZStack(alignment: .trailing) {
                    // Primary pane always stays full-width (no layout jump)
                    primaryPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Dim slightly when panel is open and not expanded
                        .overlay(
                            Color.black.opacity(selectedNote != nil && !isDetailExpanded ? 0.18 : 0)
                                .ignoresSafeArea()
                                .allowsHitTesting(false)
                                .animation(.easeInOut(duration: 0.22), value: selectedNote?.id)
                        )
                        .onTapGesture {
                            if selectedNote != nil && !isDetailExpanded { clearSelection() }
                        }

                    // Detail panel slides in from trailing edge as overlay
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
                            .frame(maxWidth: isDetailExpanded ? .infinity : 360, maxHeight: .infinity)
                        }
                        .frame(maxWidth: isDetailExpanded ? .infinity : 361)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing),
                                removal: .move(edge: .trailing)
                            )
                        )
                        .zIndex(1)
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: selectedNote?.id)
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: isDetailExpanded)
            }
            .background(isDarkMode ? Color(red: 0.095, green: 0.095, blue: 0.10) : Color(red: 0.972, green: 0.972, blue: 0.976))
            .colorScheme(isDarkMode ? .dark : .light)
            .jottAppTypography()
            .task(id: selectionSyncSignature) {
                syncSelection()
            }
            .background { libraryScaffoldNotificationListener }
        )
    }

    private var primaryPane: AnyView {
        AnyView(Group {
            if isSearching {
                // Unified search results (all modes, includes subnotes)
                SearchResultsView(
                    results: searchResults,
                    query: searchText,
                    mode: searchMode,
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
                case .outline:
                    LibraryOutlineView(
                        viewModel: viewModel,
                        selectedNote: selectedNote,
                        onSelect: { note in select(note: note) }
                    )
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
        ScrollView(showsIndicators: false) {
            if visibleNotes.isEmpty {
                LibraryEmptyState(
                    title: searchText.isEmpty ? "No notes yet" : "No notes match this search",
                    message: searchText.isEmpty ? "Capture something and it will land here." : "Try a broader query or switch views."
                )
                .padding(.top, 56)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 248, maximum: 320), spacing: 16, alignment: .top)],
                    spacing: 16
                ) {
                    ForEach(sortedVisibleNotes, id: \.id) { note in
                        LibraryMinimalNoteCard(
                            note: note,
                            estimatedHeight: 180,
                            isSelected: selectedNoteIDs.contains(note.id),
                            isDarkMode: isDarkMode,
                            subnoteCount: viewModel.subnoteCount(of: note.id),
                            isDragSelecting: $isDragSelectingNotes,
                            onActivate: { modifiers in
                                select(note: note, modifiers: modifiers)
                            },
                            onDragSelect: {
                                dragSelect(note: note)
                            }
                        )
                    }
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

    private var libraryScaffoldNotificationListener: some View {
        Color.clear.frame(width: 0, height: 0)
    }

    private func gridCardStyle(for note: Note) -> JottNoteCardStyle {
        let lineCount = note.text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        if note.text.contains("![") || lineCount >= 6 {
            return .feature
        }
        if lineCount >= 3 || note.text.count > 90 {
            return .regular
        }
        return .compact
    }

    private func select(note: Note, modifiers: NSEvent.ModifierFlags = []) {
        let relevantModifiers = modifiers.intersection([.shift, .command, .control])

        if relevantModifiers.contains(.shift) {
            applyRangeSelection(to: note.id)
            selectedItem = .note(note.id)
            return
        }

        if relevantModifiers.contains(.command) || relevantModifiers.contains(.control) {
            if selectedNoteIDs.contains(note.id) {
                selectedNoteIDs.remove(note.id)
                if case .note(let selectedID) = selectedItem, selectedID == note.id {
                    if let fallbackID = selectedNoteIDs.first {
                        selectedItem = .note(fallbackID)
                    } else {
                        selectedItem = nil
                    }
                }
            } else {
                selectedNoteIDs.insert(note.id)
                selectedItem = .note(note.id)
                selectionAnchorNoteID = note.id
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
        withAnimation(JottMotion.content) {
            selectedItem = nil
            selectedNoteIDs.removeAll()
            selectionAnchorNoteID = nil
            isDetailExpanded = false
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
    @Binding var isDragSelecting: Bool
    let onActivate: (NSEvent.ModifierFlags) -> Void
    let onDragSelect: () -> Void
    @State private var hovered = false
    @State private var thumbnail: NSImage?

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
        return Array(cleaned.dropFirst().prefix(thumbnail == nil ? 5 : 3))
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

    // Solid card fill so it fully covers ghost cards behind it
    private var solidCardFill: Color {
        isDarkMode
            ? Color(red: 0.138, green: 0.138, blue: 0.148)
            : Color(red: 0.99, green: 0.99, blue: 0.995)
    }
    private var ghostFill: Color {
        isDarkMode
            ? Color(red: 0.118, green: 0.118, blue: 0.126)
            : Color(red: 0.945, green: 0.945, blue: 0.955)
    }
    private var ghostBorder: Color {
        isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.09)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Ghost 2 — furthest back, offset more, narrower
            if subnoteCount >= 2 {
                ghostCard(offsetY: 9, scaleX: 0.88)
            }
            // Ghost 1 — one layer back, offset less, slightly narrower
            if subnoteCount >= 1 {
                ghostCard(offsetY: 4.5, scaleX: 0.94)
            }

            // ── Main card ──
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(metadataLabel)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.72))
                    Spacer()
                    Text(relativeTimeLabel)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.58))
                }

                Spacer().frame(height: 14)

                Text(stripMarkup(from: title))
                    .font(JottTypography.noteTitle(15, weight: .medium))
                    .foregroundColor(.primary.opacity(0.88))
                    .lineLimit(thumbnail == nil ? 3 : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let previewText {
                    Spacer().frame(height: 10)
                    if let thumbnail {
                        HStack(alignment: .center, spacing: 12) {
                            Text(previewText)
                                .font(JottTypography.noteBody(12))
                                .foregroundColor(.secondary.opacity(0.70))
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(nsImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 82, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .rotationEffect(.degrees(-3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.jottBorder.opacity(0.72), lineWidth: 1)
                                )
                        }
                    } else {
                        Text(previewText)
                            .font(JottTypography.noteBody(12))
                            .foregroundColor(.secondary.opacity(0.70))
                            .lineLimit(5)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if let thumbnail {
                    Spacer().frame(height: 12)
                    HStack {
                        Spacer()
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .rotationEffect(.degrees(-3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.jottBorder.opacity(0.72), lineWidth: 1)
                            )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(minHeight: estimatedHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    // Use solid fill so ghost cards are fully hidden except their peeking bottom edge
                    .fill(subnoteCount > 0 ? solidCardFill : (isDarkMode ? Color.white.opacity(isSelected ? 0.05 : 0.016) : Color.white.opacity(isSelected ? 0.94 : 0.82)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.jottOverlayCoralAccent.opacity(isDarkMode ? 0.55 : 0.45)
                            : Color.jottBorder.opacity(hovered ? 0.72 : 0.52),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .overlay(alignment: .bottomTrailing) {
                MinimalFoldCorner(isDarkMode: isDarkMode)
                    .padding(7)
            }
            // Subnote count badge — bottom-left, away from timestamp
            .overlay(alignment: .bottomLeading) {
                if subnoteCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "square.on.square")
                            .font(.system(size: 8, weight: .medium))
                        Text("\(subnoteCount)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(isDarkMode ? .white.opacity(0.38) : .black.opacity(0.30))
                    .padding(.leading, 12).padding(.bottom, 10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture {
                onActivate(NSApp.currentEvent?.modifierFlags ?? [])
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { _ in
                        if !isDragSelecting {
                            isDragSelecting = true
                            onDragSelect()
                        }
                    }
                    .onEnded { _ in isDragSelecting = false }
            )
            .animation(JottMotion.micro, value: hovered)
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
        // Extra bottom padding so ghost cards aren't clipped by the grid cell
        .padding(.bottom, subnoteCount >= 2 ? 10 : subnoteCount >= 1 ? 5 : 0)
    }

    @ViewBuilder
    private func ghostCard(offsetY: CGFloat, scaleX: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(ghostFill)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(ghostBorder, lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: estimatedHeight)
            .scaleEffect(x: scaleX, y: 1, anchor: .top)
            .offset(y: offsetY)
            .allowsHitTesting(false)
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

// MARK: - Library Note Detail Panel

private struct LibraryNoteDetailPanel: View {
    let note: Note
    @ObservedObject var viewModel: OverlayViewModel
    let isDark: Bool
    @Binding var isExpanded: Bool
    let onClose: () -> Void

    @State private var showingSubnoteInput: Bool = false
    @State private var newSubnoteText: String = ""
    @FocusState private var subnoteFieldFocused: Bool

    // Pastel squish button color
    private var squishColor: Color {
        isDark
            ? Color(red: 0.58, green: 0.50, blue: 0.92)   // soft lavender
            : Color(red: 0.62, green: 0.52, blue: 0.96)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // ── Header ──
                HStack(spacing: 10) {
                    // Date pill
                    Text(formattedDate)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.55))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        .clipShape(Capsule())

                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.45))
                    }

                    Spacer()

                    // Expand / collapse button
                    Button {
                        withAnimation(JottMotion.content) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.55))
                            .frame(width: 26, height: 26)
                            .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse" : "Expand to full screen")

                    // Close button
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.55))
                            .frame(width: 26, height: 26)
                            .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider().opacity(isDark ? 0.10 : 0.07)

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

            // ── Squish FAB (bottom-right) ──
            Button {
                withAnimation(JottMotion.content) {
                    showingSubnoteInput = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    subnoteFieldFocused = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Subnote")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(squishColor)
                .clipShape(Capsule())
                .shadow(color: squishColor.opacity(0.45), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
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
    }

    // ── Subnote quick-add row ──
    private var subnoteInputRow: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(squishColor.opacity(0.7))
                .frame(width: 3, height: 32)

            TextField("New subnote…", text: $newSubnoteText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(isDark ? .white.opacity(0.88) : .black.opacity(0.85))
                .focused($subnoteFieldFocused)
                .onSubmit { commitSubnote() }
                .onKeyPress(.escape) {
                    cancelSubnoteInput()
                    return .handled
                }

            Button(action: commitSubnote) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(newSubnoteText.isEmpty ? .secondary.opacity(0.3) : squishColor)
            }
            .buttonStyle(.plain)
            .disabled(newSubnoteText.isEmpty)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(squishColor.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: note.modifiedAt)
    }

    private func commitSubnote() {
        let text = newSubnoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { cancelSubnoteInput(); return }
        viewModel.createSubnote(parentId: note.id, text: text)
        newSubnoteText = ""
        withAnimation(JottMotion.content) { showingSubnoteInput = false }
    }

    private func cancelSubnoteInput() {
        newSubnoteText = ""
        subnoteFieldFocused = false
        withAnimation(JottMotion.content) { showingSubnoteInput = false }
    }
}

// MARK: - Outline / Hierarchy View

private struct LibraryOutlineView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let selectedNote: Note?
    let onSelect: (Note) -> Void

    private var isDark: Bool { viewModel.isDarkMode }
    private var rootNotes: [Note] {
        viewModel.getAllNotes().filter { $0.parentId == nil }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if rootNotes.isEmpty {
                LibraryEmptyState(
                    title: "No notes yet",
                    message: "Capture something and it will land here."
                )
                .padding(.top, 56)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(rootNotes) { note in
                        OutlineNoteRow(
                            note: note,
                            isDark: isDark,
                            isSelected: selectedNote?.id == note.id,
                            onSelect: { onSelect(note) }
                        )
                    }
                }
            }
        }
    }
}

private struct OutlineNoteRow: View {
    let note: Note
    let isDark: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var hovered = false

    private var subnotes: [Note] { NoteStore.shared.subnotes(of: note.id) }
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
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return f.string(from: note.modifiedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Parent note row ──
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 12) {
                    // Left accent strip when selected
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isSelected ? Color.jottOverlayCoralAccent.opacity(0.7) : Color.clear)
                        .frame(width: 3)
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isDark ? .white.opacity(0.88) : .black.opacity(0.84))
                                .lineLimit(1)
                            Spacer()
                            Text(dateLabel)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary.opacity(0.45))
                        }

                        if let preview = bodyPreview {
                            Text(preview)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.55))
                                .lineLimit(1)
                        }

                        if !subnotes.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.35))
                                Text("\(subnotes.count) subnote\(subnotes.count == 1 ? "" : "s")")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary.opacity(0.38))
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isSelected
                                ? (isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                                : (hovered ? (isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    isSelected
                                        ? Color.jottOverlayCoralAccent.opacity(isDark ? 0.40 : 0.30)
                                        : Color.jottBorder.opacity(hovered ? 0.52 : 0.32),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { hovered = hovering }
            }

            // ── Subnote tiles (indented) ──
            if !subnotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(subnotes.prefix(3)) { sub in
                        OutlineSubnoteChip(note: sub, isDark: isDark)
                    }
                    if subnotes.count > 3 {
                        Text("··· \(subnotes.count - 3) more")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.32))
                            .padding(.leading, 8)
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 4)
            }
        }
    }
}

private struct OutlineSubnoteChip: View {
    let note: Note
    let isDark: Bool
    @State private var hovered = false

    private var title: String {
        note.text.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? "Untitled"
    }

    var body: some View {
        HStack(spacing: 8) {
            // Connector dot
            Circle()
                .fill(Color.secondary.opacity(0.22))
                .frame(width: 5, height: 5)

            Text(title)
                .font(.system(size: 12))
                .foregroundColor(isDark ? .white.opacity(0.58) : .black.opacity(0.52))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    hovered
                        ? (isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                        : (isDark ? Color.white.opacity(0.024) : Color.black.opacity(0.018))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isDark ? Color.white.opacity(hovered ? 0.10 : 0.055) : Color.black.opacity(hovered ? 0.09 : 0.048),
                            lineWidth: 1
                        )
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { hovered = hovering }
        }
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
        HStack(spacing: 12) {
            VStack(alignment: .center, spacing: 4) {
                switch item {
                case .note:
                    Image(systemName: "note.text")
                        .font(JottTypography.ui(12, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.56))
                case .reminder:
                    Image(systemName: "bell.fill")
                        .font(JottTypography.ui(12, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.56))
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                switch item {
                case .note(let note):
                    Text(noteTitle(for: note))
                        .font(JottTypography.noteTitle(13.5, weight: .medium))
                        .foregroundColor(.primary.opacity(0.88))
                        .lineLimit(1)

                    if let preview = notePreview(for: note) {
                        Text(preview)
                            .font(JottTypography.noteBody(11.5))
                            .foregroundColor(.secondary.opacity(0.56))
                            .lineLimit(1)
                    }

                    let subs = NoteStore.shared.subnotes(of: note.id)
                    if !subs.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.35))
                            Text(subs.prefix(2).compactMap {
                                $0.text.components(separatedBy: "\n")
                                    .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                            }.joined(separator: "  ·  "))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.40))
                            .lineLimit(1)
                            if subs.count > 2 {
                                Text("+\(subs.count - 2)")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary.opacity(0.28))
                            }
                        }
                    }

                case .reminder(let reminder):
                    Text(reminder.text)
                        .font(JottTypography.noteTitle(13.5, weight: .medium))
                        .foregroundColor(.primary.opacity(0.88))
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(JottTypography.ui(10, weight: .medium))
                        Text(formatTime(reminder.dueDate))
                            .font(JottTypography.ui(11))
                    }
                    .foregroundColor(.secondary.opacity(0.56))
                }
            }

            Spacer()

            if case .note(let note) = item, hovered {
                Button {
                    withAnimation(JottMotion.content) {
                        viewModel.deleteNote(note.id)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(JottTypography.ui(11, weight: .medium))
                        .foregroundColor(.red.opacity(0.55))
                        .frame(width: 26, height: 26)
                        .background(Color.red.opacity(isDarkMode ? 0.16 : 0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.96).combined(with: .opacity).animation(JottMotion.content))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Color.jottOverlaySelectorAccent.opacity(isDarkMode ? 0.12 : 0.10)
                        : (
                            isDarkMode
                                ? Color.white.opacity(hovered ? 0.034 : 0.014)
                                : Color.white.opacity(hovered ? 0.92 : 0.84)
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.jottOverlaySelectorAccent.opacity(0.24)
                        : (
                            hovered
                                ? Color.primary.opacity(isDarkMode ? 0.16 : 0.10)
                                : Color.jottBorder.opacity(0.58)
                        ),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(NSApp.currentEvent?.modifierFlags ?? [])
        }
        .onHover { hovering in
            withAnimation(JottMotion.micro) {
                hovered = hovering
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func noteTitle(for note: Note) -> String {
        let lines = note.text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.first ?? "Untitled"
    }

    private func notePreview(for note: Note) -> String? {
        let lines = note.text
            .components(separatedBy: "\n")
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
    let mode: SearchMode
    let isDark: Bool
    let selectedNote: Note?
    let onSelect: (Note) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            if results.isEmpty {
                LibraryEmptyState(
                    title: "No results",
                    message: "Nothing matched \"\(query)\". Try a different mode or refine your query."
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
    @Binding var searchMode: SearchMode
    let visibleCount: Int
    let isDarkMode: Bool
    let selectedNote: Note?
    var onDismissDetail: (() -> Void)? = nil

    private var isSearching: Bool { !searchText.isEmpty }

    var body: some View {
        HStack(spacing: 12) {
            // Title + count
            VStack(alignment: .leading, spacing: 2) {
                Text("Notes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Text("\(visibleCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            // Display mode toggle (hidden while searching)
            if !isSearching {
                HStack(spacing: 4) {
                    ForEach(LibraryDisplayMode.allCases, id: \.self) { mode in
                        modeButton(mode)
                    }
                }
                .padding(4)
                .background(isDarkMode ? Color.white.opacity(0.018) : Color.black.opacity(0.024))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.jottBorder.opacity(isDarkMode ? 0.42 : 0.46), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
            }

            Spacer(minLength: 0)

            // Search mode pills (visible while searching)
            if isSearching {
                HStack(spacing: 3) {
                    ForEach(SearchMode.allCases) { mode in
                        searchModeChip(mode)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)))
            }

            // Search field
            HStack(spacing: 8) {
                Image(systemName: isSearching ? searchMode.icon : "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSearching ? searchModeColor : .secondary.opacity(0.68))
                    .animation(.easeInOut(duration: 0.15), value: isSearching)

                TextField("Search notes & subnotes…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .frame(width: 220)

                if isSearching {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.42))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isDarkMode ? Color.white.opacity(0.022) : Color.black.opacity(0.028))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSearching
                            ? searchModeColor.opacity(0.35)
                            : Color.jottBorder.opacity(isDarkMode ? 0.46 : 0.52),
                        lineWidth: 1
                    )
                    .animation(.easeInOut(duration: 0.2), value: isSearching)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(isDarkMode ? Color.white.opacity(0.006) : Color.white.opacity(0.80))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSearching)
    }

    private var searchModeColor: Color {
        switch searchMode {
        case .normal:   return .secondary
        case .fuzzy:    return Color(red: 0.3, green: 0.7, blue: 0.5)
        case .semantic: return Color(red: 0.55, green: 0.45, blue: 0.95)
        }
    }

    @ViewBuilder
    private func searchModeChip(_ mode: SearchMode) -> some View {
        let isActive = searchMode == mode
        Button { searchMode = mode } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(mode.shortLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isActive ? .white : .secondary.opacity(0.7))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive ? modeChipColor(mode) : Color.clear)
                    .overlay(
                        Capsule().strokeBorder(
                            isActive ? Color.clear : Color.secondary.opacity(0.25),
                            lineWidth: 1
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: searchMode)
    }

    private func modeChipColor(_ mode: SearchMode) -> Color {
        switch mode {
        case .normal:   return Color.secondary.opacity(0.55)
        case .fuzzy:    return Color(red: 0.28, green: 0.65, blue: 0.48)
        case .semantic: return Color(red: 0.52, green: 0.42, blue: 0.92)
        }
    }

    private func actionChip(icon: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(.primary.opacity(0.82))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isDarkMode ? Color.white.opacity(0.022) : Color.black.opacity(0.028))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.jottBorder.opacity(isDarkMode ? 0.46 : 0.52), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func modeButton(_ mode: LibraryDisplayMode) -> some View {
        let isActive = displayMode == mode

        return Button {
            withAnimation(JottMotion.content) {
                displayMode = mode
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(mode.rawValue)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundColor(isActive ? .primary : .secondary.opacity(0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isActive
                            ? (isDarkMode ? Color.white.opacity(0.052) : Color.white.opacity(0.92))
                            : .clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.jottBorder.opacity(isDarkMode ? 0.48 : 0.40) : .clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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

private struct LibraryEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.secondary.opacity(0.34))
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.76))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(title)
                            .font(JottTypography.title(21, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

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
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isDarkMode ? Color.white.opacity(0.025) : Color.black.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color.jottBorder.opacity(0.56), lineWidth: 1)
                            )

                            // Show in Graph button
                            Button {
                                NotificationCenter.default.post(
                                    name: .jottOpenNoteInCanvas,
                                    object: note.id
                                )
                            } label: {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.78))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(isDarkMode ? Color.white.opacity(0.025) : Color.black.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(Color.jottBorder.opacity(0.56), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)

                            Button {
                                viewModel.openNoteInEditor(note)
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.78))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(isDarkMode ? Color.white.opacity(0.025) : Color.black.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(Color.jottBorder.opacity(0.56), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Updated \(relativeDate)")
                        .font(JottTypography.ui(11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                if !note.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(note.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(JottTypography.ui(11, weight: .semibold))
                                .foregroundColor(Color.tagColor(for: tag))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.tagColor(for: tag).opacity(isDarkMode ? 0.18 : 0.14))
                                )
                        }
                    }
                }

                Group {
                    if isEditing {
                        TextEditor(text: $editingText)
                            .font(.system(size: 14))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .frame(minHeight: 220)
                            .focused($isEditorFocused)
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
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.jottBorder.opacity(0.60), lineWidth: 1)
                )

            }
        }
        .onAppear {
            editingText = note.text
            isEditing = true
            DispatchQueue.main.async {
                isEditorFocused = true
            }
        }
        .onChange(of: note.id) { _, _ in
            editingText = note.text
            isEditing = true
            DispatchQueue.main.async {
                isEditorFocused = true
            }
        }
        .onChange(of: editRequestToken) { _, _ in
            editingText = note.text
            isEditing = true
            DispatchQueue.main.async {
                isEditorFocused = true
            }
        }
        .onChange(of: note.text) { _, newValue in
            if !isEditing {
                editingText = newValue
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
