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
                title: "New Subnote",
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
        let subnotes = noteStore.allNotes().filter { $0.parentId == note.id }

        return ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    metadataStrip
                    Rectangle().fill(ds.hairline).frame(height: 1).padding(.horizontal, 20)

                    IOSBlockContentView(blocks: liveNote.blocks, isDark: scheme == .dark)
                        .onTapGesture(count: 2) { enterEditing() }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)

                    if !subnotes.isEmpty {
                        subnotesSection
                    } else {
                        Spacer().frame(height: 100)
                    }
                }
            }
            .onTapGesture(count: 2) { enterEditing() }

            Button { showNewSubnote = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 17, weight: .medium))
                    Text("New Subnote")
                        .font(.jottBody(15, weight: .medium))
                }
                .foregroundStyle(ds.accent)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(ds.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ds.accent.opacity(0.22), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 28)
        }
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

    // MARK: - Subnotes section (only rendered when subnotes exist)

    @ViewBuilder
    private var subnotesSection: some View {
        let subnotes = noteStore.allNotes().filter { $0.parentId == note.id }

        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(ds.hairline).frame(height: 1).padding(.horizontal, 20)

            HStack {
                Text("SUBNOTES")
                    .font(.jottMono(10, weight: .medium))
                    .foregroundStyle(ds.inkFaintest)
                    .tracking(0.6)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            ForEach(subnotes) { sub in
                NavigationLink(value: sub) {
                    SubnoteRow(note: sub, ds: ds)
                }
                .buttonStyle(.plain)

                if sub.id != subnotes.last?.id {
                    Rectangle().fill(ds.hairline).frame(height: 1).padding(.horizontal, 20)
                }
            }

            Spacer().frame(height: 100)
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
        isEditing = true
    }

    private func commitEdit() {
        var updated = liveNote
        let clean = editBlocks.filter { $0.type != .table || !$0.tableHeaders.isEmpty }
        guard !clean.isEmpty else { return }
        updated.blocks = clean
        updated.modifiedAt = Date()
        noteStore.upsertNote(updated)
        isEditing = false
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

// MARK: - iOS block text editor (UITextView + format toolbar)

struct IOSBlockTextEditor: UIViewRepresentable {
    @Binding var blocks: [Block]
    let isDark: Bool
    var autoFocus: Bool = false
    var onBlocksChange: (([Block]) -> Void)?
    var onInsertTable: ((Int, Int) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.font = UIFont.systemFont(ofSize: 16)
        tv.text = context.coordinator.displayText(for: blocks)
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
        context.coordinator.parent = self
        let proposed = context.coordinator.displayText(for: blocks)
        if tv.text != proposed {
            let sel = tv.selectedRange
            tv.text = proposed
            let len = (tv.text as NSString).length
            if sel.upperBound <= len { tv.selectedRange = sel }
        }
        context.coordinator.updateColors(isDark: isDark)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IOSBlockTextEditor
        weak var textView: UITextView?

        // Voice input state
        weak var micButton: UIButton?
        var micInkColor: UIColor = .gray
        var micActiveColor: UIColor = .systemPurple
        private var voiceStartLocation: Int? = nil
        private var voiceTextLength: Int = 0

        init(_ parent: IOSBlockTextEditor) { self.parent = parent }

        func displayText(for blocks: [Block]) -> String {
            var number = 1
            return blocks.map { block in
                let text = block.plainText
                switch block.type {
                case .bulletItem:
                    number = 1
                    return "• \(text)"
                case .numberedItem:
                    defer { number += 1 }
                    return "\(number). \(text)"
                case .taskItem:
                    number = 1
                    return "\(block.checked ? "☑" : "☐") \(text)"
                case .quote:
                    number = 1
                    return "❝ \(text)"
                case .heading:
                    number = 1
                    return text
                default:
                    number = 1
                    return text
                }
            }.joined(separator: "\n")
        }

        func extractBlocks(from text: String) -> [Block] {
            let lines = text.components(separatedBy: "\n")
            let result = lines.map { line -> Block in
                if line.hasPrefix("• ") {
                    return Block(type: .bulletItem, spans: [TextSpan(String(line.dropFirst(2)))])
                }
                if line.hasPrefix("☐ ") || line.hasPrefix("☑ ") {
                    return Block(type: .taskItem, spans: [TextSpan(String(line.dropFirst(2)))], checked: line.hasPrefix("☑ "))
                }
                if line.hasPrefix("❝ ") {
                    return Block(type: .quote, spans: [TextSpan(String(line.dropFirst(2)))])
                }
                if let range = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                    return Block(type: .numberedItem, spans: [TextSpan(String(line[range.upperBound...]))])
                }
                return Block(type: .paragraph, spans: [TextSpan(line)])
            }
            return result.isEmpty ? [Block(type: .paragraph, spans: [TextSpan("")])] : result
        }

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
            let updated = extractBlocks(from: tv.text)
            parent.blocks = updated
            parent.onBlocksChange?(updated)
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", range.length == 0 else { return true }
            return !handleReturn(in: tv)
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
            let updated = extractBlocks(from: tv.text)
            parent.blocks = updated
            parent.onBlocksChange?(updated)
        }

        // MARK: Format commands

        func wrapSelection(opening: String, closing: String) {
            // Inline span styling needs a native attributed-text pass. Keep this
            // out of the text model so formatting buttons never inject markup.
        }

        func toggleLinePrefix(_ prefix: String) {
            guard let tv = textView else { return }
            let nsText = tv.text as NSString
            let cursor = tv.selectedRange.location
            let lineNSRange = currentLineTextRange(in: tv, cursor: cursor)
            let line = nsText.substring(with: lineNSRange)
            let stripped = strippedLinePrefix(from: line)
            let newLine = line.hasPrefix(prefix) ? stripped : prefix + stripped
            guard let start = tv.position(from: tv.beginningOfDocument, offset: lineNSRange.location),
                  let end = tv.position(from: tv.beginningOfDocument, offset: lineNSRange.location + lineNSRange.length),
                  let range = tv.textRange(from: start, to: end) else { return }
            tv.replace(range, withText: newLine)
            tv.selectedRange = NSRange(location: lineNSRange.location + (newLine as NSString).length, length: 0)
            let updated = extractBlocks(from: tv.text)
            parent.blocks = updated
            parent.onBlocksChange?(updated)
        }

        @discardableResult
        private func handleReturn(in tv: UITextView) -> Bool {
            let nsText = tv.text as NSString
            let cursor = tv.selectedRange.location
            let lineRange = currentLineTextRange(in: tv, cursor: cursor)
            let line = nsText.substring(with: lineRange)

            if line.hasPrefix("• ") {
                let content = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if content.isEmpty {
                    replaceText(in: tv, range: NSRange(location: lineRange.location, length: 2), with: "")
                } else {
                    insertText("\n• ", in: tv)
                }
                return true
            }

            if line.hasPrefix("☐ ") || line.hasPrefix("☑ ") {
                let content = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if content.isEmpty {
                    replaceText(in: tv, range: NSRange(location: lineRange.location, length: 2), with: "")
                } else {
                    insertText("\n☐ ", in: tv)
                }
                return true
            }

            if line.hasPrefix("❝ ") {
                let content = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if content.isEmpty {
                    replaceText(in: tv, range: NSRange(location: lineRange.location, length: 2), with: "")
                } else {
                    insertText("\n❝ ", in: tv)
                }
                return true
            }

            if let number = numberedPrefix(in: line) {
                let content = (line as NSString).substring(from: number.length).trimmingCharacters(in: .whitespaces)
                if content.isEmpty {
                    replaceText(in: tv, range: NSRange(location: lineRange.location, length: number.length), with: "")
                } else {
                    insertText("\n\(number.value + 1). ", in: tv)
                }
                return true
            }

            return false
        }

        private func currentLineTextRange(in tv: UITextView, cursor: Int) -> NSRange {
            let nsText = tv.text as NSString
            let length = nsText.length
            if cursor == length, length > 0, nsText.character(at: length - 1) == 10 {
                return NSRange(location: cursor, length: 0)
            }
            let safeCursor = min(max(cursor, 0), length)
            let fullLineRange = nsText.lineRange(for: NSRange(location: safeCursor, length: 0))
            let hasNewline = fullLineRange.length > 0 && nsText.character(at: NSMaxRange(fullLineRange) - 1) == 10
            return NSRange(location: fullLineRange.location, length: fullLineRange.length - (hasNewline ? 1 : 0))
        }

        private func numberedPrefix(in line: String) -> (value: Int, length: Int)? {
            let nsLine = line as NSString
            guard let match = try? NSRegularExpression(pattern: #"^(\d+)\. "#)
                .firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
                return nil
            }
            return (Int(nsLine.substring(with: match.range(at: 1))) ?? 1, match.range.length)
        }

        private func strippedLinePrefix(from line: String) -> String {
            for prefix in ["• ", "☐ ", "☑ ", "❝ "] where line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
            if let number = numberedPrefix(in: line) {
                return (line as NSString).substring(from: number.length)
            }
            return line
        }

        private func insertText(_ text: String, in tv: UITextView) {
            let selected = tv.selectedRange
            replaceText(in: tv, range: selected, with: text)
            tv.selectedRange = NSRange(location: selected.location + (text as NSString).length, length: 0)
        }

        private func replaceText(in tv: UITextView, range: NSRange, with text: String) {
            guard let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
                  let end = tv.position(from: tv.beginningOfDocument, offset: range.location + range.length),
                  let textRange = tv.textRange(from: start, to: end) else { return }
            tv.replace(textRange, withText: text)
            let updated = extractBlocks(from: tv.text)
            parent.blocks = updated
            parent.onBlocksChange?(updated)
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
    private weak var coordinator: IOSBlockTextEditor.Coordinator?

    init(coordinator: IOSBlockTextEditor.Coordinator, isDark: Bool) {
        super.init(frame: CGRect(x: 0, y: 0, width: 100, height: 52))
        self.coordinator = coordinator
        autoresizingMask = [.flexibleWidth]
        clipsToBounds = true

        backgroundColor = isDark
            ? UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 0.97)
            : UIColor(red: 0.97, green: 0.97, blue: 0.975, alpha: 0.97)

        let line = UIView()
        line.backgroundColor = isDark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.09)
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 2
        row.alignment = .center
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)

        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.topAnchor.constraint(equalTo: topAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),

            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: line.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        let inkMute = isDark
            ? UIColor(white: 0.68, alpha: 1)
            : UIColor(red: 0.36, green: 0.36, blue: 0.39, alpha: 1)
        let accentColor = isDark
            ? UIColor(red: 0.58, green: 0.48, blue: 0.88, alpha: 1)
            : UIColor(red: 0.42, green: 0.30, blue: 0.76, alpha: 1)

        addTextBtn(row, title: "B", weight: .bold,    color: inkMute, sel: #selector(bold))
        addTextBtn(row, title: "I", weight: .regular, italic: true,     color: inkMute, sel: #selector(italic))
        addTextBtn(row, title: "U", weight: .regular, underline: true,  color: inkMute, sel: #selector(underline))
        addTextBtn(row, title: "S", weight: .regular, strike: true,     color: inkMute, sel: #selector(strike))
        addSeparator(row, isDark: isDark)
        addIconBtn(row, sf: "list.bullet",       color: inkMute,     sel: #selector(bullet))
        addIconBtn(row, sf: "list.number",       color: inkMute,     sel: #selector(numbered))
        addIconBtn(row, sf: "checklist",         color: inkMute,     sel: #selector(task))
        addIconBtn(row, sf: "text.quote",        color: inkMute,     sel: #selector(quote))
        addSeparator(row, isDark: isDark)
        addIconBtn(row, sf: "textformat.size",   color: inkMute,     sel: #selector(heading))
        addIconBtn(row, sf: "highlighter",       color: inkMute,     sel: #selector(highlight))
        addIconBtn(row, sf: "chevron.left.forwardslash.chevron.right", color: inkMute, sel: #selector(code))
        addIconBtn(row, sf: "tablecells",        color: accentColor, sel: #selector(table))
        addSeparator(row, isDark: isDark)
        let micBtn = addIconBtn(row, sf: "mic",  color: inkMute,     sel: #selector(mic))
        coordinator.registerMicButton(micBtn, inkColor: inkMute, activeColor: accentColor)
        addIconBtn(row, sf: "keyboard.chevron.compact.down", color: inkMute, sel: #selector(dismiss))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }

    private func addSeparator(_ stack: UIStackView, isDark: Bool) {
        let sep = UIView()
        sep.backgroundColor = isDark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.black.withAlphaComponent(0.10)
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 22).isActive = true
        stack.addArrangedSubview(sep)
        stack.setCustomSpacing(6, after: sep)
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
        btn.backgroundColor = .clear
        btn.layer.cornerRadius = 7
        btn.layer.masksToBounds = true
        btn.widthAnchor.constraint(equalToConstant: 38).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 38).isActive = true
        stack.addArrangedSubview(btn)
    }

    @discardableResult
    private func addIconBtn(_ stack: UIStackView, sf: String, color: UIColor, sel: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        btn.setImage(UIImage(systemName: sf, withConfiguration: cfg), for: .normal)
        btn.tintColor = color
        btn.addTarget(self, action: sel, for: .touchUpInside)
        btn.backgroundColor = .clear
        btn.layer.cornerRadius = 7
        btn.layer.masksToBounds = true
        btn.widthAnchor.constraint(equalToConstant: 38).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 38).isActive = true
        stack.addArrangedSubview(btn)
        return btn
    }

    // MARK: - Actions

    @objc private func bold()      { coordinator?.wrapSelection(opening: "", closing: "") }
    @objc private func italic()    { coordinator?.wrapSelection(opening: "", closing: "") }
    @objc private func underline() { coordinator?.wrapSelection(opening: "", closing: "") }
    @objc private func strike()    { coordinator?.wrapSelection(opening: "", closing: "") }
    @objc private func highlight() { coordinator?.wrapSelection(opening: "", closing: "") }
    @objc private func bullet()    { coordinator?.toggleLinePrefix("• ")     }
    @objc private func numbered()  { coordinator?.toggleLinePrefix("1. ")    }
    @objc private func task()      { coordinator?.toggleLinePrefix("☐ ")     }
    @objc private func quote()     { coordinator?.toggleLinePrefix("❝ ")     }
    @objc private func code()      { coordinator?.wrapSelection(opening: "", closing: "") }
    @objc private func heading()   { coordinator?.wrapSelection(opening: "", closing: "") }
    @objc private func table()     { coordinator?.insertTable() }
    @objc private func mic()       { coordinator?.toggleVoice() }
    @objc private func dismiss()   { coordinator?.dismissKeyboard() }
}

struct IOSBlockContentView: View {
    let blocks: [Block]
    let isDark: Bool

    private var ds: JottDS { JottDS(isDark: isDark) }
    private var displayBlocks: [Block] {
        let visible = blocks.filter { block in
            switch block.type {
            case .paragraph, .heading, .bulletItem, .numberedItem, .taskItem, .quote:
                return !block.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default:
                return true
            }
        }
        return visible.isEmpty ? [Block(type: .paragraph, spans: [TextSpan("")])] : visible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(displayBlocks.enumerated()), id: \.element.id) { index, block in
                blockView(block, orderedNumber: orderedNumber(at: index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func orderedNumber(at index: Int) -> Int? {
        guard displayBlocks.indices.contains(index),
              displayBlocks[index].type == .numberedItem else { return nil }
        var number = 1
        var i = index - 1
        while displayBlocks.indices.contains(i), displayBlocks[i].type == .numberedItem {
            number += 1
            i -= 1
        }
        return number
    }

    @ViewBuilder
    private func blockView(_ block: Block, orderedNumber: Int?) -> some View {
        switch block.type {
        case .heading:
            IOSSpansText(spans: block.spans, size: block.level == 1 ? 22 : 18, weight: .semibold, color: ds.ink)
                .padding(.top, 4)
        case .bulletItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(ds.accent).frame(width: 14)
                IOSSpansText(spans: block.spans, size: 15, weight: .regular, color: ds.ink)
            }
        case .numberedItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(orderedNumber ?? 1).")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(ds.inkMute)
                    .frame(width: 24, alignment: .trailing)
                IOSSpansText(spans: block.spans, size: 15, weight: .regular, color: ds.ink)
            }
        case .taskItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: block.checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(block.checked ? ds.accent : ds.inkMute)
                    .frame(width: 18)
                IOSSpansText(spans: block.spans, size: 15, weight: .regular, color: ds.ink)
            }
        case .quote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(ds.accent.opacity(0.42)).frame(width: 2)
                IOSSpansText(spans: block.spans, size: 15, weight: .regular, color: ds.inkMute)
            }
        case .table:
            IOSReadOnlyTableBlock(block: block, ds: ds)
        case .divider:
            Rectangle().fill(ds.hairlineMid).frame(height: 1).padding(.vertical, 4)
        default:
            IOSSpansText(spans: block.spans, size: 15, weight: .regular, color: ds.ink)
        }
    }
}

private struct IOSSpansText: View {
    let spans: [TextSpan]
    let size: CGFloat
    let weight: Font.Weight
    let color: Color

    var body: some View {
        Text(attributedText)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()
        for span in spans.isEmpty ? [TextSpan("")] : spans {
            var value = AttributedString(span.text)
            value.font = span.code ? .system(size: size - 1, design: .monospaced) : .system(size: size, weight: weight)
            value.foregroundColor = color
            if span.underline { value.underlineStyle = .single }
            if span.strikethrough { value.strikethroughStyle = .single }
            if span.highlight { value.backgroundColor = Color.yellow.opacity(0.35) }
            if span.italic { value.inlinePresentationIntent = .emphasized }
            if span.bold { value.inlinePresentationIntent = .stronglyEmphasized }
            result += value
        }
        return result
    }
}

private struct IOSReadOnlyTableBlock: View {
    let block: Block
    let ds: JottDS

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(block.tableHeaders.indices, id: \.self) { col in
                        tableCell(block.tableHeaders[col], isHeader: true)
                    }
                }
                ForEach(block.tableRows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(block.tableHeaders.indices, id: \.self) { col in
                            tableCell(cellValue(row: row, col: col), isHeader: false)
                        }
                    }
                }
            }
            .background(ds.surfaceAlt.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ds.hairlineMid, lineWidth: 0.8))
        }
    }

    private func tableCell(_ text: String, isHeader: Bool) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.jottBody(14, weight: isHeader ? .semibold : .regular))
            .foregroundStyle(isHeader ? ds.ink : ds.inkMute)
            .padding(.horizontal, 10)
            .frame(minWidth: 116, minHeight: 38, alignment: .leading)
            .background(isHeader ? ds.accentSoft : ds.surface)
            .overlay(Rectangle().stroke(ds.hairlineMid, lineWidth: 0.5))
    }

    private func cellValue(row: Int, col: Int) -> String {
        guard block.tableRows.indices.contains(row),
              block.tableRows[row].indices.contains(col) else { return "" }
        return block.tableRows[row][col]
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
