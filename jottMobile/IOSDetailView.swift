import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Detail view (read + edit)

struct IOSDetailView: View {
    let note: Note
    let onDelete: () -> Void

    @ObservedObject private var noteStore: NoteStore
    @Environment(\.colorScheme) private var scheme
    @State private var isEditing = false
    @State private var editBlocks: [Block] = []
    @State private var showDeleteConfirm = false
    @State private var showNewSubnote = false
    @State private var autosaveTask: Task<Void, Never>? = nil
    @State private var showTagEditor = false

    init(note: Note, onDelete: @escaping () -> Void) {
        self.note = note
        self.onDelete = onDelete
        self._noteStore = ObservedObject(wrappedValue: NoteStore.shared)
    }

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }

    private var liveNote: Note {
        noteStore.allNotes().first(where: { $0.id == note.id }) ?? note
    }

    var body: some View {
        ZStack {
            ds.canvas.ignoresSafeArea()
            Group {
                if isEditing {
                    editorView
                } else {
                    readView
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onDisappear {
            autosaveTask?.cancel()
            if isEditing { commitEdit() }
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Move to Recently Deleted", role: .destructive) {
                noteStore.deleteNote(note.id)
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showNewSubnote) {
            IOSNewNoteComposerView(
                title: "New Linked Note",
                folderId: liveNote.folderId,
                parentId: note.id
            ) { _ in
            }
        }
        .sheet(isPresented: $showTagEditor) {
            IOSTagEditorView(tags: liveNote.tags) { updatedTags in
                var updated = liveNote
                updated.tags = updatedTags
                updated.modifiedAt = Date()
                noteStore.upsertNote(updated)
            }
        }
        .navigationDestination(for: Note.self) { sub in
            IOSDetailView(note: sub, onDelete: {})
        }
    }

    // MARK: - Read mode

    private var readView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                metadataStrip
                Rectangle().fill(ds.hairline).frame(height: 1).padding(.horizontal, 20)

                MarkdownRichView(
                    text: liveNote.text,
                    isDarkMode: scheme == .dark,
                    onDoubleTap: { enterEditing() }
                ) { paragraphText in
                    IOSParagraphView(text: paragraphText, isDark: scheme == .dark)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

                subnotesSection
            }
        }
        .onTapGesture(count: 2) { enterEditing() }
    }

    // MARK: - Metadata strip

    private var metadataStrip: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(jottMetaDate(liveNote.modifiedAt))
                    .font(.jottMono(10, weight: .medium))
                    .foregroundStyle(ds.inkFaintest)
                    .tracking(0.4)
                Text(jottRelativeDate(liveNote.modifiedAt))
                    .font(.jottMono(10))
                    .foregroundStyle(ds.inkFaintest)
                    .tracking(0.4)
            }
            if liveNote.isPinned {
                Text("PINNED")
                    .font(.jottMono(9, weight: .medium))
                    .foregroundStyle(ds.accent.opacity(0.45))
                    .tracking(0.6)
            }
            Spacer()
            Button { showTagEditor = true } label: {
                if liveNote.tags.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.system(size: 10, weight: .medium))
                        Text("Tags")
                            .font(.jottCaption(11, weight: .medium))
                    }
                    .foregroundStyle(ds.inkFaintest)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ds.surfaceAlt, in: Capsule())
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(liveNote.tags, id: \.self) { tag in
                                JottTagChip(tag: tag, ds: ds)
                            }
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(ds.inkFaintest)
                        }
                    }
                    .frame(maxWidth: 180)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Subnotes section

    @ViewBuilder
    private var subnotesSection: some View {
        let subnotes = noteStore.allNotes().filter { $0.parentId == note.id }

        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(ds.hairline).frame(height: 1).padding(.horizontal, 20)

            HStack {
                Text("LINKED NOTES")
                    .font(.jottMono(10, weight: .medium))
                    .foregroundStyle(ds.inkFaintest)
                    .tracking(0.6)
                Spacer()
                Button {
                    showNewSubnote = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("New")
                            .font(.jottCaption(12, weight: .medium))
                    }
                    .foregroundStyle(ds.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(ds.accentSoft, in: Capsule())
                    .overlay(Capsule().strokeBorder(ds.accent.opacity(0.20), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, subnotes.isEmpty ? 20 : 10)

            ForEach(subnotes) { sub in
                NavigationLink(value: sub) {
                    SubnoteRow(note: sub, ds: ds)
                }
                .buttonStyle(.plain)

                if sub.id != subnotes.last?.id {
                    Rectangle().fill(ds.hairline).frame(height: 1).padding(.horizontal, 20)
                }
            }

            if subnotes.isEmpty {
                Text("No linked notes yet")
                    .font(.jottBody(13))
                    .foregroundStyle(ds.inkFaintest)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            } else {
                Spacer().frame(height: 24)
            }
        }
    }

    // MARK: - Edit mode

    private var editorView: some View {
        IOSBlockNoteEditor(
            blocks: $editBlocks,
            isDark: scheme == .dark,
            autoFocus: true
        ) { newBlocks in
            scheduleAutosave(blocks: newBlocks)
        }
        .background(ds.canvas)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if isEditing {
                Button("Done") { commitEdit() }
                    .fontWeight(.semibold)
                    .foregroundStyle(ds.accent)
            } else {
                Button { enterEditing() } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(ds.inkMute)
                }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if !isEditing {
                Menu {
                    Button {
                        noteStore.togglePin(note.id)
                    } label: {
                        Label(liveNote.isPinned ? "Unpin" : "Pin",
                              systemImage: liveNote.isPinned ? "pin.slash" : "pin")
                    }
                    Button { shareNote() } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(ds.inkMute)
                }
            }
        }
    }

    // MARK: - Helpers

    private func enterEditing() {
        editBlocks = liveNote.blocks
        withAnimation(JottMotion.content) { isEditing = true }
    }

    private func commitEdit() {
        var updated = liveNote
        let clean = editBlocks.filter { $0.type != .table || !$0.tableHeaders.isEmpty }
        guard !clean.isEmpty else { return }
        updated.blocks = clean
        updated.modifiedAt = Date()
        noteStore.upsertNote(updated)
        withAnimation(JottMotion.content) { isEditing = false }
    }

    private func scheduleAutosave(blocks newBlocks: [Block]) {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let clean = newBlocks.filter { $0.type != .table || !$0.tableHeaders.isEmpty }
            guard !clean.isEmpty else { return }
            var updated = liveNote
            updated.blocks = clean
            updated.modifiedAt = Date()
            await MainActor.run { noteStore.upsertNote(updated) }
        }
    }

    private func shareNote() {
        let text = liveNote.text
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}

// MARK: - iOS Markdown Editor (UITextView + format toolbar)

struct IOSMarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    let isDark: Bool
    var autoFocus: Bool = false
    var onTextChange: ((String) -> Void)?
    var onInsertTable: ((Int, Int) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.font = UIFont.systemFont(ofSize: 16)
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 80, right: 16)
        tv.keyboardDismissMode = .interactive
        context.coordinator.textView = tv
        context.coordinator.updateColors(isDark: isDark)

        let toolbar = IOSFormatToolbarView(coordinator: context.coordinator, isDark: isDark)
        tv.inputAccessoryView = toolbar

        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                tv.becomeFirstResponder()
            }
        }

        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            let sel = tv.selectedRange
            tv.text = text
            let len = (tv.text as NSString).length
            if sel.upperBound <= len { tv.selectedRange = sel }
        }
        context.coordinator.updateColors(isDark: isDark)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IOSMarkdownEditor
        weak var textView: UITextView?

        // Voice input state
        weak var micButton: UIButton?
        var micInkColor: UIColor = .gray
        var micActiveColor: UIColor = .systemPurple
        private var voiceStartLocation: Int? = nil
        private var voiceTextLength: Int = 0

        init(_ parent: IOSMarkdownEditor) { self.parent = parent }

        func updateColors(isDark: Bool) {
            guard let tv = textView else { return }
            let color = UIColor(
                red: isDark ? 0.95 : 0.14,
                green: isDark ? 0.95 : 0.14,
                blue: isDark ? 0.95 : 0.15,
                alpha: 1
            )
            if tv.textColor != color { tv.textColor = color }
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            parent.onTextChange?(tv.text)
        }

        func registerMicButton(_ btn: UIButton, inkColor: UIColor, activeColor: UIColor) {
            micButton = btn
            micInkColor = inkColor
            micActiveColor = activeColor
        }

        func toggleVoice() {
            Task { @MainActor in
                let sm = SpeechManager.shared
                if sm.isRecording {
                    sm.stopRecording()
                    self.micButton?.tintColor = self.micInkColor
                    let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                    self.micButton?.setImage(UIImage(systemName: "mic", withConfiguration: cfg), for: .normal)
                    self.voiceStartLocation = nil
                    self.voiceTextLength = 0
                } else {
                    guard let tv = self.textView else { return }
                    self.voiceStartLocation = tv.selectedRange.location
                    self.voiceTextLength = 0
                    self.micButton?.tintColor = self.micActiveColor
                    let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                    self.micButton?.setImage(UIImage(systemName: "stop.circle.fill", withConfiguration: cfg), for: .normal)
                    sm.startRecording { [weak self] partial in
                        self?.insertVoiceText(partial, isFinal: false)
                    } onFinal: { [weak self] final in
                        self?.insertVoiceText(final, isFinal: true)
                        let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                        self?.micButton?.setImage(UIImage(systemName: "mic", withConfiguration: cfg), for: .normal)
                        self?.micButton?.tintColor = self?.micInkColor
                    }
                }
            }
        }

        private func insertVoiceText(_ text: String, isFinal: Bool) {
            guard let tv = textView, let start = voiceStartLocation else { return }
            let nsText = tv.text as NSString
            let totalLen = nsText.length
            let replaceStart = min(start, totalLen)
            let replaceLen = min(voiceTextLength, totalLen - replaceStart)
            guard let startPos = tv.position(from: tv.beginningOfDocument, offset: replaceStart),
                  let endPos = tv.position(from: tv.beginningOfDocument, offset: replaceStart + replaceLen),
                  let textRange = tv.textRange(from: startPos, to: endPos) else { return }
            let insert = isFinal ? text + " " : text
            tv.replace(textRange, withText: insert)
            voiceTextLength = isFinal ? 0 : (insert as NSString).length
            if isFinal { voiceStartLocation = nil }
            parent.text = tv.text
            parent.onTextChange?(tv.text)
        }

        // MARK: Format commands

        func wrapSelection(opening: String, closing: String) {
            guard let tv = textView, let selRange = tv.selectedTextRange else { return }
            let selected = tv.text(in: selRange) ?? ""
            tv.replace(selRange, withText: opening + selected + closing)
            if selected.isEmpty, let pos = tv.position(from: selRange.start, offset: opening.count) {
                tv.selectedTextRange = tv.textRange(from: pos, to: pos)
            }
            parent.text = tv.text
        }

        func toggleLinePrefix(_ prefix: String) {
            guard let tv = textView else { return }
            let nsText = tv.text as NSString
            let cursor = tv.selectedRange.location
            let lineNSRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            let line = nsText.substring(with: lineNSRange)
            let newLine = line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : prefix + line
            guard let start = tv.position(from: tv.beginningOfDocument, offset: lineNSRange.location),
                  let end = tv.position(from: tv.beginningOfDocument, offset: lineNSRange.location + lineNSRange.length),
                  let range = tv.textRange(from: start, to: end) else { return }
            tv.replace(range, withText: newLine)
            parent.text = tv.text
        }

        func insertTable(rows: Int = 2, columns: Int = 2) {
            parent.onInsertTable?(rows, columns)
        }

        func dismissKeyboard() {
            textView?.resignFirstResponder()
        }
    }
}

// MARK: - Format toolbar (UIKit inputAccessoryView)

private final class IOSFormatToolbarView: UIView {
    private weak var coordinator: IOSMarkdownEditor.Coordinator?

    init(coordinator: IOSMarkdownEditor.Coordinator, isDark: Bool) {
        super.init(frame: CGRect(x: 0, y: 0, width: 100, height: 104))
        self.coordinator = coordinator
        autoresizingMask = [.flexibleWidth]
        clipsToBounds = false

        backgroundColor = isDark
            ? UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 0.97)
            : UIColor(red: 0.97, green: 0.97, blue: 0.975, alpha: 0.97)

        let line = UIView()
        line.backgroundColor = isDark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.09)
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        let vertical = UIStackView()
        vertical.axis = .vertical
        vertical.spacing = 6
        vertical.alignment = .fill
        vertical.distribution = .fillEqually
        vertical.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vertical)

        let topRow = UIStackView()
        topRow.axis = .horizontal
        topRow.spacing = 4
        topRow.alignment = .center
        topRow.distribution = .fill

        let bottomRow = UIStackView()
        bottomRow.axis = .horizontal
        bottomRow.spacing = 4
        bottomRow.alignment = .center
        bottomRow.distribution = .fill

        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.topAnchor.constraint(equalTo: topAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),

            vertical.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            vertical.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            vertical.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 8),
            vertical.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        vertical.addArrangedSubview(topRow)
        vertical.addArrangedSubview(bottomRow)

        let inkMute = isDark
            ? UIColor(white: 0.68, alpha: 1)
            : UIColor(red: 0.36, green: 0.36, blue: 0.39, alpha: 1)
        let accentColor = isDark
            ? UIColor(red: 0.58, green: 0.48, blue: 0.88, alpha: 1)
            : UIColor(red: 0.42, green: 0.30, blue: 0.76, alpha: 1)

        addTextBtn(topRow, title: "B",  weight: .bold,    color: inkMute, sel: #selector(bold))
        addTextBtn(topRow, title: "I",  weight: .regular, italic: true, color: inkMute, sel: #selector(italic))
        addTextBtn(topRow, title: "U",  weight: .regular, underline: true, color: inkMute, sel: #selector(underline))
        addTextBtn(topRow, title: "S",  weight: .regular, strike: true, color: inkMute, sel: #selector(strike))
        addIconBtn(topRow, sf: "highlighter",                              color: inkMute, sel: #selector(highlight))
        addIconBtn(topRow, sf: "chevron.left.forwardslash.chevron.right",  color: inkMute, sel: #selector(code))
        let micBtn = addIconBtn(topRow, sf: "mic", color: inkMute, sel: #selector(mic))
        coordinator.registerMicButton(micBtn, inkColor: inkMute, activeColor: accentColor)

        addIconBtn(bottomRow, sf: "list.bullet",       color: inkMute,   sel: #selector(bullet))
        addIconBtn(bottomRow, sf: "list.number",       color: inkMute,   sel: #selector(numbered))
        addIconBtn(bottomRow, sf: "checklist",         color: inkMute,   sel: #selector(task))
        addIconBtn(bottomRow, sf: "text.quote",        color: inkMute,   sel: #selector(quote))
        addIconBtn(bottomRow, sf: "textformat.size",   color: inkMute,   sel: #selector(heading))
        addIconBtn(bottomRow, sf: "tablecells",        color: accentColor, sel: #selector(table))
        addIconBtn(bottomRow, sf: "keyboard.chevron.compact.down", color: inkMute, sel: #selector(dismiss))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 104)
    }

    // MARK: - Button factory

    private func addTextBtn(_ stack: UIStackView, title: String, weight: UIFont.Weight, italic: Bool = false, underline: Bool = false, strike: Bool = false, color: UIColor, sel: Selector) {
        let btn = UIButton(type: .system)
        var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
        let baseFont = italic
            ? UIFont.italicSystemFont(ofSize: 15)
            : UIFont.systemFont(ofSize: 15, weight: weight)
        attrs[.font] = baseFont
        if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if strike    { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        btn.setAttributedTitle(NSAttributedString(string: title, attributes: attrs), for: .normal)
        btn.addTarget(self, action: sel, for: .touchUpInside)
        btn.backgroundColor = UIColor(white: 1.0, alpha: 0.04)
        btn.layer.cornerRadius = 8
        btn.layer.masksToBounds = true
        btn.widthAnchor.constraint(equalToConstant: 42).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stack.addArrangedSubview(btn)
    }

    @discardableResult
    private func addIconBtn(_ stack: UIStackView, sf: String, color: UIColor, sel: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        btn.setImage(UIImage(systemName: sf, withConfiguration: cfg), for: .normal)
        btn.tintColor = color
        btn.addTarget(self, action: sel, for: .touchUpInside)
        btn.backgroundColor = UIColor(white: 1.0, alpha: 0.04)
        btn.layer.cornerRadius = 8
        btn.layer.masksToBounds = true
        btn.widthAnchor.constraint(equalToConstant: 42).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stack.addArrangedSubview(btn)
        return btn
    }

    // MARK: - Actions

    @objc private func bold()      { coordinator?.wrapSelection(opening: "**", closing: "**") }
    @objc private func italic()    { coordinator?.wrapSelection(opening: "*",  closing: "*")  }
    @objc private func underline() { coordinator?.wrapSelection(opening: "__", closing: "__") }
    @objc private func strike()    { coordinator?.wrapSelection(opening: "~~", closing: "~~") }
    @objc private func highlight() { coordinator?.wrapSelection(opening: "==", closing: "==") }
    @objc private func bullet()    { coordinator?.toggleLinePrefix("- ")     }
    @objc private func numbered()  { coordinator?.toggleLinePrefix("1. ")    }
    @objc private func task()      { coordinator?.toggleLinePrefix("- [ ] ") }
    @objc private func quote()     { coordinator?.toggleLinePrefix("> ")     }
    @objc private func code()      { coordinator?.wrapSelection(opening: "`", closing: "`")   }
    @objc private func heading()   { coordinator?.toggleLinePrefix("## ")    }
    @objc private func table()     { coordinator?.insertTable() }
    @objc private func mic()       { coordinator?.toggleVoice() }
    @objc private func dismiss()   { coordinator?.dismissKeyboard() }
}

// MARK: - iOS paragraph renderer

struct IOSParagraphView: View {
    let text: String
    let isDark: Bool

    private var ds: JottDS { JottDS(isDark: isDark) }

    var body: some View {
        Text(mdInlineAttributedString(
            text,
            baseFont: .system(size: 15),
            baseColor: ds.ink,
            baseSize: 15
        ))
        .font(.system(size: 15))
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Subnote row

struct SubnoteRow: View {
    let note: Note
    let ds: JottDS

    var body: some View {
        let preview = jottNotePreview(note)
        HStack(spacing: 12) {
            Text("•")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ds.accent.opacity(0.50))
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ds.ink)
                    .lineLimit(1)
                if !preview.body.isEmpty {
                    Text(preview.body)
                        .font(.system(size: 12))
                        .foregroundStyle(ds.inkMute)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ds.inkFaintest)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Tag editor sheet

struct IOSTagEditorView: View {
    let initialTags: [String]
    let onSave: ([String]) -> Void

    @State private var tags: [String]
    @State private var newTag: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @FocusState private var fieldFocused: Bool

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }
    private var trimmed: String { newTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    init(tags: [String], onSave: @escaping ([String]) -> Void) {
        self.initialTags = tags
        self.onSave = onSave
        self._tags = State(initialValue: tags)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ds.canvas.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    // Input row
                    HStack(spacing: 10) {
                        Image(systemName: "tag")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ds.accent)
                        TextField("Add tag", text: $newTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textFieldStyle(.plain)
                            .font(.jottBody(15))
                            .foregroundStyle(ds.ink)
                            .focused($fieldFocused)
                            .onSubmit { addTag() }
                        if !newTag.isEmpty {
                            Button(action: addTag) {
                                Text("Add")
                                    .font(.jottBody(14, weight: .semibold))
                                    .foregroundStyle(trimmed.isEmpty || tags.contains(trimmed) ? ds.inkFaintest : ds.accent)
                            }
                            .buttonStyle(.plain)
                            .disabled(trimmed.isEmpty || tags.contains(trimmed))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(ds.surface)
                    .overlay(Rectangle().fill(ds.hairline).frame(height: 1), alignment: .bottom)

                    if tags.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tag")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(ds.inkFaintest)
                            Text("No tags yet")
                                .font(.jottBody(15))
                                .foregroundStyle(ds.inkFaint)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 60)
                    } else {
                        List {
                            ForEach(tags, id: \.self) { tag in
                                HStack {
                                    Text("#\(tag)")
                                        .font(.jottBody(15))
                                        .foregroundStyle(ds.ink)
                                    Spacer()
                                }
                                .listRowBackground(ds.surface)
                            }
                            .onDelete { offsets in
                                tags.remove(atOffsets: offsets)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ds.inkMute)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(tags)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(ds.accent)
                }
            }
            .onAppear { fieldFocused = true }
        }
    }

    private func addTag() {
        let t = trimmed
        guard !t.isEmpty, !tags.contains(t) else { return }
        withAnimation { tags.append(t) }
        newTag = ""
    }
}
