import SwiftUI
import Combine

// MARK: - SubnoteOutlinerView

struct SubnoteOutlinerView: View {
    let parentNote: Note
    @ObservedObject var viewModel: OverlayViewModel
    let isDark: Bool

    @State private var editingId: UUID? = nil
    @State private var editText: String = ""
    @State private var pendingDeleteId: UUID? = nil
    @State private var deleteTask: Task<Void, Never>? = nil
    @State private var orderedIds: [UUID] = []

    private var subnotes: [Note] { viewModel.subnotes(of: parentNote.id) }
    private var visibleSubnotes: [Note] {
        let active = subnotes.filter { $0.id != pendingDeleteId }
        if orderedIds.isEmpty { return active }
        let idSet = Set(active.map(\.id))
        let ordered = orderedIds.compactMap { id -> Note? in
            guard idSet.contains(id) else { return nil }
            return active.first(where: { $0.id == id })
        }
        // Append any notes not yet in orderedIds (newly added)
        let remaining = active.filter { !orderedIds.contains($0.id) }
        return ordered + remaining
    }

    private var accent: Color {
        isDark ? Color(red: 0.58, green: 0.50, blue: 0.92)
               : Color(red: 0.62, green: 0.52, blue: 0.96)
    }

    var body: some View {
        if subnotes.isEmpty && pendingDeleteId == nil { EmptyView() } else {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ──
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 1)
                        .frame(maxWidth: 20)

                    Text("Subnotes")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.40))
                        .fixedSize()

                    Text("\(subnotes.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(accent.opacity(0.70))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.10), in: Capsule())

                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 1)
                }
                .padding(.bottom, 12)

                // ── Rows ──
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(visibleSubnotes) { subnote in
                        SubnoteRowCard(
                            note: subnote,
                            depth: 0,
                            isDark: isDark,
                            accent: accent,
                            editingId: $editingId,
                            editText: $editText,
                            viewModel: viewModel,
                            onDelete: { handleDelete($0) }
                        )
                        .transition(.asymmetric(
                            insertion: .offset(y: -4).combined(with: .opacity),
                            removal:   .opacity
                        ))
                    }
                }

                // ── Undo toast ──
                if pendingDeleteId != nil {
                    HStack(spacing: 8) {
                        Text("Deleted")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.60))
                        Button("Undo") { undoDelete() }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(accent)
                            .buttonStyle(.plain)
                    }
                    .padding(.top, 10)
                    .transition(.offset(y: 4).combined(with: .opacity))
                }
            }
            .padding(.top, 28)
            .animation(JottMotion.content, value: visibleSubnotes.map(\.id))
            .onAppear {
                if orderedIds.isEmpty {
                    orderedIds = subnotes.map(\.id)
                }
            }
            .onChange(of: subnotes.map(\.id)) { _, newIds in
                // Merge: keep existing order, append new arrivals
                let current = Set(orderedIds)
                let incoming = Set(newIds)
                orderedIds = orderedIds.filter { incoming.contains($0) }
                    + newIds.filter { !current.contains($0) }
            }
        }
    }

    private func handleDelete(_ note: Note) {
        withAnimation(JottMotion.content) { pendingDeleteId = note.id }
        deleteTask?.cancel()
        deleteTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                viewModel.deleteSubnote(note.id)
                withAnimation(JottMotion.content) { pendingDeleteId = nil }
            }
        }
    }

    private func undoDelete() {
        deleteTask?.cancel()
        deleteTask = nil
        withAnimation(JottMotion.content) { pendingDeleteId = nil }
    }
}

// MARK: - SubnoteRowCard

private struct SubnoteRowCard: View {
    let note: Note
    let depth: Int
    let isDark: Bool
    let accent: Color
    @Binding var editingId: UUID?
    @Binding var editText: String
    @ObservedObject var viewModel: OverlayViewModel
    var onDelete: (Note) -> Void

    @State private var hovered = false
    @State private var editHeight: CGFloat = SubnoteTextEditor.minHeight

    private let maxDepth = 2
    private var children: [Note] { viewModel.subnotes(of: note.id) }
    private var hasChildren: Bool { !children.isEmpty }
    private var isEditing: Bool { editingId == note.id }

    private var firstLine: String {
        note.text.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? note.text
    }

    private var rowFill: Color {
        if isEditing { return isDark ? accent.opacity(0.09) : accent.opacity(0.06) }
        if hovered   { return isDark ? Color.white.opacity(0.045) : Color.black.opacity(0.032) }
        return .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            rowContent
                .contextMenu {
                    Button("Edit") { startEditing() }
                    if depth < maxDepth {
                        Button("Add child") { addChild() }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { onDelete(note) }
                }

            // Children indented
            if hasChildren {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(children) { child in
                        SubnoteRowCard(
                            note: child,
                            depth: min(depth + 1, maxDepth),
                            isDark: isDark,
                            accent: accent,
                            editingId: $editingId,
                            editText: $editText,
                            viewModel: viewModel,
                            onDelete: onDelete
                        )
                    }
                }
                .padding(.leading, 20)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(accent.opacity(0.20))
                        .frame(width: 1.5)
                        .padding(.vertical, 4)
                        .offset(x: 8)
                }
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(alignment: .top, spacing: 0) {
            // Leading dot — top-aligned so it stays pinned when editor grows
            Circle()
                .fill(isEditing ? accent.opacity(0.80) : accent.opacity(hovered ? 0.55 : 0.35))
                .frame(width: 5, height: 5)
                .padding(.top, 9)
                .padding(.trailing, 10)
                .animation(.easeInOut(duration: 0.12), value: isEditing)
                .animation(.easeInOut(duration: 0.12), value: hovered)

            // Text or editor
            if isEditing {
                SubnoteTextEditor(
                    text: $editText,
                    height: $editHeight,
                    isDark: isDark,
                    onFocusChange: { focused in if !focused { commitEdit() } },
                    onDismiss: { commitEdit() }
                )
                .frame(height: editHeight)
                .onChange(of: editingId) { _, _ in
                    editHeight = SubnoteTextEditor.minHeight
                }
                .onDisappear { if editingId == note.id { commitEdit() } }
            } else {
                Text(firstLine)
                    .font(.system(size: 13, weight: depth == 0 ? .regular : .light))
                    .foregroundColor(isDark ? .white.opacity(0.80) : .black.opacity(0.72))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { startEditing() }
            }

            // Open button — open subnote standalone
            if !isEditing && depth == 0 {
                Button {
                    viewModel.openSubnote(note)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary.opacity(hovered ? 0.65 : 0.35))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.85, pressedOpacity: 0.70))
                .padding(.leading, 6)
                .animation(.easeInOut(duration: 0.12), value: hovered)
            }

            // Delete button — always visible, brighter on hover
            if !isEditing {
                Button {
                    withAnimation(JottMotion.content) { onDelete(note) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary.opacity(hovered ? 0.70 : 0.30))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.85, pressedOpacity: 0.70))
                .padding(.leading, 6)
                .animation(.easeInOut(duration: 0.12), value: hovered)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isEditing ? accent.opacity(0.30) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.10)) { hovered = hovering }
        }
        .animation(.easeInOut(duration: 0.12), value: hovered)
        .animation(.easeInOut(duration: 0.15), value: isEditing)
    }

    private func startEditing() {
        editHeight = SubnoteTextEditor.minHeight
        editText = note.text
        withAnimation(.easeInOut(duration: 0.15)) { editingId = note.id }
    }

    private func commitEdit() {
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            var updated = note
            updated.text = text
            updated.modifiedAt = Date()
            NoteStore.shared.upsertNote(updated)
        } else {
            viewModel.deleteSubnote(note.id)
        }
        viewModel.objectWillChange.send()
        withAnimation(.easeInOut(duration: 0.15)) { editingId = nil }
        editText = ""
    }

    private func addChild() {
        let child = Note(text: " ", parentId: note.id)
        NoteStore.shared.upsertNote(child)
        viewModel.objectWillChange.send()
        editHeight = SubnoteTextEditor.minHeight
        editText = ""
        editingId = child.id
    }
}

// MARK: - AddSubnoteRow

struct AddSubnoteRow: View {
    let parentNote: Note
    @ObservedObject var viewModel: OverlayViewModel
    let isDark: Bool
    var onDismiss: (() -> Void)? = nil

    @State private var text = ""
    @State private var editorHeight: CGFloat = SubnoteTextEditor.minHeight
    @State private var isFocused = false
    @State private var debounceTask: Task<Void, Never>? = nil

    private var accent: Color {
        isDark ? Color(red: 0.58, green: 0.50, blue: 0.92)
               : Color(red: 0.62, green: 0.52, blue: 0.96)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(accent.opacity(isFocused ? 0.70 : 0.25))
                .frame(width: 4.5, height: 4.5)
                .padding(.top, 9)
                .animation(.easeInOut(duration: 0.12), value: isFocused)

            ZStack(alignment: .topLeading) {
                SubnoteTextEditor(
                    text: $text,
                    height: $editorHeight,
                    isDark: isDark,
                    onFocusChange: { isFocused = $0 },
                    onDismiss: { dismissRow() }
                )
                if text.isEmpty {
                    Text("+ Add…")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.20))
                        .allowsHitTesting(false)
                        .padding(.top, 2)
                }
            }
            .frame(height: editorHeight)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(accent.opacity(isFocused ? 0.25 : 0.08), lineWidth: 0.8)
                )
        )
        .animation(.easeInOut(duration: 0.12), value: isFocused)
        .onAppear {
            if viewModel.subnoteSessionParentId == parentNote.id,
               !viewModel.subnoteSessionText.isEmpty {
                text = viewModel.subnoteSessionText
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                viewModel.autoSaveSubnoteDraft(parentId: parentNote.id, text: trimmed)
            }
        }
        .onChange(of: text) { _, newValue in scheduleAutoSave(newValue) }
    }

    private func scheduleAutoSave(_ value: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                await MainActor.run {
                    viewModel.autoSaveSubnoteDraft(parentId: parentNote.id, text: trimmed)
                }
            }
        }
    }

    private func dismissRow() {
        debounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            viewModel.discardSubnoteDraft(parentId: parentNote.id)
        } else {
            viewModel.autoSaveSubnoteDraft(parentId: parentNote.id, text: trimmed)
        }
        text = ""
        onDismiss?()
    }
}

// MARK: - SubnoteTextEditor

struct SubnoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let isDark: Bool
    let onFocusChange: (Bool) -> Void
    let onDismiss: () -> Void

    static let minHeight: CGFloat = 26
    static let maxHeight: CGFloat = 110

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller = false
        sv.hasHorizontalScroller = false
        sv.drawsBackground = false
        sv.borderType = .noBorder
        sv.autohidesScrollers = true

        let tv = DetailNoteTextView()
        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.font = .systemFont(ofSize: 13, weight: .regular)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.registerForDraggedTypes([.fileURL, .png, .tiff, .string])
        tv.string = ""

        sv.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.scrollView = sv

        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? DetailNoteTextView else { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, text.count), length: 0))
            context.coordinator.updateHeight()
        }
        let color: NSColor = isDark
            ? NSColor.white.withAlphaComponent(0.88)
            : NSColor.black.withAlphaComponent(0.82)
        if tv.textColor != color { tv.textColor = color }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SubnoteTextEditor
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(_ parent: SubnoteTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            updateHeight()
        }

        func textDidBeginEditing(_ notification: Notification) { parent.onFocusChange(true) }
        func textDidEndEditing(_ notification: Notification)   { parent.onFocusChange(false) }

        func updateHeight() {
            guard let tv = textView,
                  let lm = tv.layoutManager,
                  let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc)
            let newH = max(SubnoteTextEditor.minHeight,
                          min(SubnoteTextEditor.maxHeight, ceil(used.height) + 2))
            scrollView?.hasVerticalScroller = newH >= SubnoteTextEditor.maxHeight
            if abs(parent.height - newH) > 0.5 {
                DispatchQueue.main.async { self.parent.height = newH }
            }
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.cancelOperation(_:)) {
                parent.onDismiss()
                return true
            }
            // Plain Enter → new line; Shift+Enter → also new line
            if sel == #selector(NSResponder.insertNewline(_:)) ||
               sel == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                tv.insertText("\n", replacementRange: tv.selectedRange())
                return true
            }
            return false
        }
    }
}
