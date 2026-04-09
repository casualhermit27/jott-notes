import SwiftUI
import Combine

// MARK: - SubnoteOutlinerView
// Clean card-style subnote list shown below note content.
// Max 3 depth levels. Double-tap to edit inline. Children indent under parent.

struct SubnoteOutlinerView: View {
    let parentNote: Note
    @ObservedObject var viewModel: OverlayViewModel
    let isDark: Bool

    @State private var collapsed: Set<UUID> = []
    @State private var editingId: UUID? = nil
    @State private var editText: String = ""

    // Undo delete — delay actual deletion so user can undo within 3s
    @State private var pendingDeleteId: UUID? = nil
    @State private var deleteTask: Task<Void, Never>? = nil

    private var subnotes: [Note] { viewModel.subnotes(of: parentNote.id) }
    private var visibleSubnotes: [Note] { subnotes.filter { $0.id != pendingDeleteId } }

    private var accentColor: Color {
        isDark
            ? Color(red: 0.58, green: 0.50, blue: 0.92)
            : Color(red: 0.62, green: 0.52, blue: 0.96)
    }

    var body: some View {
        if subnotes.isEmpty && pendingDeleteId == nil { EmptyView() } else {
            VStack(alignment: .leading, spacing: 0) {
                // Section header
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(accentColor.opacity(0.6))
                        .frame(width: 2, height: 12)
                        .clipShape(Capsule())

                    Text("SUBNOTES")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("·  \(totalCount)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.38))
                }
                .padding(.bottom, 10)
                .padding(.top, 20)

                // Subnote rows
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleSubnotes) { subnote in
                        SubnoteRowCard(
                            note: subnote,
                            depth: 0,
                            isDark: isDark,
                            accentColor: accentColor,
                            collapsed: $collapsed,
                            editingId: $editingId,
                            editText: $editText,
                            viewModel: viewModel,
                            onDelete: { handleDelete($0) }
                        )
                    }
                }

                // Undo toast
                if pendingDeleteId != nil {
                    HStack(spacing: 8) {
                        Text("Subnote deleted")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                        Button("Undo") { undoDelete() }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(accentColor)
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07), lineWidth: 1)
                            )
                    )
                    .padding(.top, 4)
                    .transition(.asymmetric(
                        insertion: .offset(y: 4).combined(with: .opacity),
                        removal:   .opacity
                    ).animation(JottMotion.content))
                }
            }
        }
    }

    private var totalCount: Int {
        func count(_ id: UUID) -> Int {
            let children = viewModel.subnotes(of: id)
            return children.count + children.map { count($0.id) }.reduce(0, +)
        }
        return count(parentNote.id)
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
    let accentColor: Color
    @Binding var collapsed: Set<UUID>
    @Binding var editingId: UUID?
    @Binding var editText: String
    @ObservedObject var viewModel: OverlayViewModel
    var onDelete: (Note) -> Void

    @State private var hovered = false
    @State private var editHeight: CGFloat = SubnoteTextEditor.minHeight
    @State private var editIsFocused = false

    private let maxDepth = 2
    private var children: [Note] { viewModel.subnotes(of: note.id) }
    private var hasChildren: Bool { !children.isEmpty }
    private var isCollapsed: Bool { collapsed.contains(note.id) }
    private var isEditing: Bool { editingId == note.id }

    private var extraLineCount: Int {
        let lines = note.text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return max(0, lines.count - 1)
    }

    private var rowFill: Color {
        if hovered { return isDark ? Color.white.opacity(0.055) : Color.black.opacity(0.038) }
        return isDark ? Color.white.opacity(0.028) : Color.black.opacity(0.020)
    }

    private var rowBorder: Color {
        if isDark { return Color.white.opacity(hovered ? 0.10 : 0.055) }
        return Color.black.opacity(hovered ? 0.09 : 0.048)
    }

    @ViewBuilder private var leadingIcon: some View {
        if hasChildren {
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    if isCollapsed { collapsed.remove(note.id) }
                    else           { collapsed.insert(note.id) }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.45))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
        } else {
            Circle()
                .fill(accentColor.opacity(depth == 0 ? 0.45 : 0.25))
                .frame(width: 5, height: 5)
                .padding(.leading, 4.5)
                .padding(.trailing, 4.5)
        }
    }

    @ViewBuilder private var trailingBadges: some View {
        if extraLineCount > 0 && !isEditing {
            Text("+\(extraLineCount)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary.opacity(0.45))
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.07))
                .clipShape(Capsule())
        }
        if hasChildren && isCollapsed {
            Text("\(children.count)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(accentColor.opacity(0.8))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(accentColor.opacity(0.12))
                .clipShape(Capsule())
        }
        if hovered && !isEditing {
            Menu {
                Button("Edit") { startEditing() }
                if depth < maxDepth {
                    Button("Add child") { addChild() }
                }
                Divider()
                Button("Delete", role: .destructive) { onDelete(note) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.45))
                    .frame(width: 22, height: 22)
                    .background(isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .transition(.opacity.animation(.easeInOut(duration: 0.12)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            rowContent
                .contextMenu {
                    Button("Edit") { startEditing() }
                    if depth < maxDepth {
                        Button("Add child") { addChild() }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { onDelete(note) }
                }

            // Children (indented)
            if hasChildren && !isCollapsed {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(children) { child in
                        SubnoteRowCard(
                            note: child,
                            depth: min(depth + 1, maxDepth),
                            isDark: isDark,
                            accentColor: accentColor,
                            collapsed: $collapsed,
                            editingId: $editingId,
                            editText: $editText,
                            viewModel: viewModel,
                            onDelete: onDelete
                        )
                    }
                }
                .padding(.leading, 18)
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(alignment: .center, spacing: 8) {
            if depth > 0 {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accentColor.opacity(0.28 - CGFloat(depth) * 0.06))
                    .frame(width: 2, height: 20)
            }

            leadingIcon

            if isEditing {
                SubnoteTextEditor(
                    text: $editText,
                    height: $editHeight,
                    isDark: isDark,
                    onFocusChange: { focused in
                        editIsFocused = focused
                        if !focused { commitEdit() }
                    },
                    onDismiss: { cancelEdit() }
                )
                .frame(height: editHeight)
                .onChange(of: editingId) { _, _ in
                    editHeight = SubnoteTextEditor.minHeight
                }
            } else {
                Text(firstLine)
                    .font(.system(size: 12.5, weight: depth == 0 ? .medium : .regular))
                    .foregroundColor(isDark ? .white.opacity(0.78) : .black.opacity(0.72))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { startEditing() }
            }

            Spacer(minLength: 0)
            trailingBadges
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(rowBorder, lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { hovered = hovering }
        }
    }

    private var firstLine: String {
        note.text.components(separatedBy: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? note.text
    }

    private func startEditing() {
        editHeight = SubnoteTextEditor.minHeight
        editText = note.text
        editingId = note.id
    }

    private func commitEdit() {
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            var updated = note
            updated.text = text
            updated.modifiedAt = Date()
            NoteStore.shared.upsertNote(updated)
        } else {
            // Nothing typed — remove the stub (handles abandoned "Add child")
            viewModel.deleteSubnote(note.id)
        }
        viewModel.objectWillChange.send()
        editingId = nil
        editText = ""
    }

    private func cancelEdit() {
        editingId = nil
        editText = ""
    }

    private func addChild() {
        let child = Note(text: " ", parentId: note.id)
        NoteStore.shared.upsertNote(child)
        viewModel.objectWillChange.send()
        editHeight = SubnoteTextEditor.minHeight
        editText = ""
        editingId = child.id
        collapsed.remove(note.id)
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
    @State private var hovered = false
    @State private var debounceTask: Task<Void, Never>? = nil

    private var accent: Color {
        isDark ? Color(red: 0.58, green: 0.50, blue: 0.92)
               : Color(red: 0.62, green: 0.52, blue: 0.96)
    }

    private var cardFill: Color {
        if isFocused { return isDark ? Color.white.opacity(0.055) : Color.black.opacity(0.038) }
        if hovered   { return isDark ? Color.white.opacity(0.038) : Color.black.opacity(0.025) }
        return isDark ? Color.white.opacity(0.018) : Color.black.opacity(0.012)
    }

    private var cardBorder: Color {
        if isFocused { return accent.opacity(0.45) }
        return isDark ? Color.white.opacity(hovered ? 0.10 : 0.055)
                      : Color.black.opacity(hovered ? 0.09 : 0.048)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(accent.opacity(isFocused ? 0.7 : 0.35))
                .frame(width: 5, height: 5)
                .padding(.leading, 4.5)
                .padding(.trailing, 4.5)
                .padding(.top, 6)
                .animation(.easeInOut(duration: 0.15), value: isFocused)

            ZStack(alignment: .topLeading) {
                SubnoteTextEditor(
                    text: $text,
                    height: $editorHeight,
                    isDark: isDark,
                    onFocusChange: { isFocused = $0 },
                    onDismiss: { dismissRow() }
                )
                if text.isEmpty {
                    Text("Add subnote…")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.28))
                        .allowsHitTesting(false)
                        .padding(.top, 1)
                }
            }
            .frame(height: editorHeight)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(cardBorder, lineWidth: 1)
                )
        )
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.12)) { hovered = hovering } }
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.12), value: hovered)
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
        .onChange(of: text) { _, newValue in
            scheduleAutoSave(newValue)
        }
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
            // Save immediately so content isn't lost if debounce hadn't fired yet
            viewModel.autoSaveSubnoteDraft(parentId: parentNote.id, text: trimmed)
        }
        text = ""
        onDismiss?()
    }
}

// MARK: - SubnoteTextEditor
// Growing NSTextView: Enter & Shift+Enter both insert newlines, Escape dismisses.
// Expands up to maxHeight, then scrolls internally. Dropdown stays fixed.

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

        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.font = .systemFont(ofSize: 12.5, weight: .medium)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.string = ""

        sv.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.scrollView = sv

        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
        }

        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? NSTextView else { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, text.count), length: 0))
            context.coordinator.updateHeight()
        }
        let color: NSColor = isDark
            ? NSColor.white.withAlphaComponent(0.9)
            : NSColor.black.withAlphaComponent(0.85)
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

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

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
            if sel == #selector(NSResponder.insertNewline(_:)) ||
               sel == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                tv.insertText("\n", replacementRange: tv.selectedRange())
                return true
            }
            return false
        }
    }
}
